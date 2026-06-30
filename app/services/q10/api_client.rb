# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Q10
  class ApiClient
    class Error < StandardError; end
    class NotFoundError < Error; end

    def initialize(config: Rails.application.config_for(:q10).deep_symbolize_keys)
      @config = config
    end

    def enabled?
      @config[:enabled]
    end

    def fetch_estudiante(numero_identificacion:)
      raise Error, "La integración Q10 está deshabilitada." unless enabled?
      raise Error, "Numero_identificacion es obligatorio." if numero_identificacion.blank?

      encoded_id = URI.encode_www_form_component(numero_identificacion.to_s.strip)
      uri = URI("#{base_url}/estudiantes/#{encoded_id}")

      response = perform_with_fallbacks(uri, method: "GET") { |attempt_uri, headers| perform_get(attempt_uri, headers) }
      raise NotFoundError, "Estudiante no encontrado en Q10." if response.code.to_i == 404

      handle_response(response)

      { success: true, data: parsed_body, status: @last_response.code.to_i }
    rescue JSON::ParserError
      raise Error, "Q10 devolvió una respuesta no válida."
    end

    def fetch_tipos_identificacion(limit: 30, offset: 1)
      raise Error, "La integración Q10 está deshabilitada." unless enabled?

      uri = URI("#{base_url}/tiposidentificacion")
      uri.query = URI.encode_www_form(Limit: limit, Offset: offset)

      handle_response(perform_with_fallbacks(uri, method: "GET") { |attempt_uri, headers| perform_get(attempt_uri, headers) })

      { success: true, data: parsed_body, status: @last_response.code.to_i }
    rescue JSON::ParserError
      raise Error, "Q10 devolvió una respuesta no válida."
    end

    def fetch_creditos(numero_identificacion:)
      raise Error, "La integración Q10 está deshabilitada." unless enabled?
      raise Error, "Numero_identificacion es obligatorio." if numero_identificacion.blank?

      uri = URI("#{base_url}/creditos")
      uri.query = URI.encode_www_form(
        Consecutivo_periodo: consecutivo_periodo,
        Numero_identificacion: numero_identificacion
      )

      handle_response(perform_with_fallbacks(uri, method: "GET") { |attempt_uri, headers| perform_get(attempt_uri, headers) })
      filtered = filter_by_numero_identificacion(parsed_body, numero_identificacion)

      { success: true, data: filtered, status: @last_response.code.to_i }
    rescue JSON::ParserError
      raise Error, "Q10 devolvió una respuesta no válida."
    end

    def report_pago_credito(payload)
      raise Error, "La integración Q10 está deshabilitada." unless enabled?
      raise Error, "El payload del pago es obligatorio." if payload.blank?

      uri = URI("#{base_url}/pagos/creditos")
      body = payload.to_json

      response = perform_with_fallbacks(uri, method: "POST") do |attempt_uri, headers|
        perform_post(attempt_uri, headers, body)
      end
      @last_response = response
      @parsed_body = parse_json(response.body)

      if response.is_a?(Net::HTTPSuccess)
        return { success: true, data: parsed_body, status: response.code.to_i }
      end

      if duplicate_payment_report?(response.code.to_i, parsed_body)
        Rails.logger.info("[Q10] Reporte de pago ya existía en Q10; se trata como exitoso (idempotente).")
        return { success: true, data: parsed_body, status: response.code.to_i, idempotent: true }
      end

      raise Error, "Q10 respondió con error #{response.code}: #{@parsed_body}"
    rescue JSON::ParserError
      raise Error, "Q10 devolvió una respuesta no válida."
    end

    private

    def handle_response(response)
      @last_response = response
      @parsed_body = parse_json(response.body)

      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "Q10 respondió con error #{response.code}: #{@parsed_body}"
      end

      @parsed_body
    end

    attr_reader :parsed_body

    def perform_with_fallbacks(uri, method: "GET")
      subscription_key = @config[:subscription_key].to_s
      api_key = @config[:api_key].to_s
      last_response = nil

      auth_attempts(subscription_key, api_key).each_with_index do |attempt, index|
        attempt_uri = uri_with_extra_query(uri, attempt[:extra_query])
        response = yield(attempt_uri, attempt[:headers])
        log_attempt(index: index + 1, uri: attempt_uri, headers: attempt[:headers], response: response, method: method)
        return response unless missing_subscription_key?(response)

        last_response = response
      end

      last_response || yield(uri, build_headers(subscription_key: subscription_key, api_key: api_key))
    end

    def auth_attempts(subscription_key, api_key)
      headers = build_headers(subscription_key: subscription_key, api_key: api_key)
      [
        { headers: headers, extra_query: {} },
        { headers: headers, extra_query: { "subscription-key" => subscription_key } },
        { headers: headers, extra_query: { "api-key" => api_key } },
        { headers: headers, extra_query: { "subscription-key" => subscription_key, "api-key" => api_key } }
      ]
    end

    def perform_get(uri, headers)
      perform_request(Net::HTTP::Get, uri, headers)
    end

    def perform_post(uri, headers, body)
      perform_request(Net::HTTP::Post, uri, headers, body: body)
    end

    def perform_request(request_class, uri, headers, body: nil)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = @config[:open_timeout].to_i
      http.read_timeout = @config[:read_timeout].to_i

      request = request_class.new(uri.request_uri)
      headers.each { |k, v| request[k] = v if v.present? }
      request["Content-Type"] = "application/json"
      request.body = body if body.present?

      http.request(request)
    rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError, OpenSSL::SSL::SSLError => e
      raise Error, "No fue posible conectar con Q10 (#{e.class}: #{e.message})."
    end

    def build_headers(subscription_key:, api_key:)
      {
        "Cache-Control" => "no-cache",
        "Ocp-Apim-Subscription-Key" => subscription_key,
        "ocp-apim-subscription-key" => subscription_key,
        "Subscription-Key" => subscription_key,
        "subscription-key" => subscription_key,
        "ApiKey" => api_key,
        "api-key" => api_key,
        "x-api-key" => api_key
      }
    end

    def missing_subscription_key?(response)
      return false unless response.code.to_i == 401

      response.body.to_s.downcase.include?("missing subscription key")
    end

    def uri_with_extra_query(base_uri, extra_query)
      return base_uri if extra_query.blank?

      current = URI.decode_www_form(base_uri.query.to_s)
      copy = base_uri.dup
      copy.query = URI.encode_www_form(current + extra_query.to_a)
      copy
    end

    def log_attempt(index:, uri:, headers:, response:, method: "GET")
      Rails.logger.info(
        "[Q10] intento #{index} #{method} #{uri} sub=#{mask(headers['Ocp-Apim-Subscription-Key'])} " \
        "api=#{mask(headers['ApiKey'])} code=#{response.code}"
      )
    end

    def mask(value)
      return "blank" if value.blank?
      return "*" * value.length if value.length <= 8

      "#{value[0, 4]}...#{value[-4, 4]}"
    end

    def parse_json(body)
      return {} if body.blank?

      JSON.parse(body)
    end

    def filter_by_numero_identificacion(payload, numero_identificacion)
      expected = normalize_identificacion(numero_identificacion)
      return [] if expected.blank? || !payload.is_a?(Array)

      payload.select do |credit|
        credit.is_a?(Hash) &&
          normalize_identificacion(credit["Numero_identificacion"]) == expected
      end
    end

    def normalize_identificacion(value)
      value.to_s.strip.upcase
    end

    def base_url
      @config[:base_url].to_s.chomp("/")
    end

    def consecutivo_periodo
      @config[:consecutivo_periodo]
    end

    def duplicate_payment_report?(status_code, body)
      return true if status_code == 409

      text = duplicate_report_text(body)
      return false if text.blank?

      text.match?(
        /ya existe|ya fue registrad|duplicad|already|registrado previamente|pago repetido|existe un pago|fue reportad/
      )
    end

    def duplicate_report_text(body)
      case body
      when Hash
        body.values.flat_map { |value| duplicate_report_text(value) }.join(" ")
      when Array
        body.flat_map { |value| duplicate_report_text(value) }.join(" ")
      else
        body.to_s
      end.downcase
    end
  end
end
