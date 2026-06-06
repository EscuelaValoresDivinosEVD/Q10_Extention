# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Q10
  class ApiClient
    class Error < StandardError; end

    def initialize(config: Rails.application.config_for(:q10).deep_symbolize_keys)
      @config = config
    end

    def enabled?
      @config[:enabled]
    end

    def fetch_creditos(numero_identificacion:)
      raise Error, "La integración Q10 está deshabilitada." unless enabled?
      raise Error, "Numero_identificacion es obligatorio." if numero_identificacion.blank?

      uri = URI("#{base_url}/creditos")
      query_params = {
        Consecutivo_periodo: consecutivo_periodo,
        Numero_identificacion: numero_identificacion
      }
      uri.query = URI.encode_www_form(query_params)

      response = perform_get_with_fallbacks(uri)
      parsed_body = parse_json(response.body)

      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "Q10 respondió con error #{response.code}: #{parsed_body}"
      end

      filtered = filter_by_numero_identificacion(parsed_body, numero_identificacion)

      { success: true, data: filtered, status: response.code.to_i }
    rescue JSON::ParserError
      raise Error, "Q10 devolvió una respuesta no válida."
    end

    def report_pago_credito(payload)
      raise Error, "La integración Q10 está deshabilitada." unless enabled?
      raise Error, "El payload del pago es obligatorio." if payload.blank?

      uri = URI("#{base_url}/pagos/creditos")
      response = perform_post_with_fallbacks(uri, payload.to_json)
      parsed_body = parse_json(response.body)

      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "Q10 respondió con error #{response.code}: #{parsed_body}"
      end

      { success: true, data: parsed_body, status: response.code.to_i }
    rescue JSON::ParserError
      raise Error, "Q10 devolvió una respuesta no válida."
    end

    private

    def perform_get_with_fallbacks(uri)
      subscription_key = @config[:subscription_key].to_s
      api_key = @config[:api_key].to_s

      attempts = [
        { headers: build_headers(subscription_key: subscription_key, api_key: api_key), extra_query: {} },
        { headers: build_headers(subscription_key: subscription_key, api_key: api_key), extra_query: { "subscription-key" => subscription_key } },
        { headers: build_headers(subscription_key: subscription_key, api_key: api_key), extra_query: { "api-key" => api_key } },
        { headers: build_headers(subscription_key: subscription_key, api_key: api_key), extra_query: { "subscription-key" => subscription_key, "api-key" => api_key } }
      ]

      last_response = nil
      attempts.each_with_index do |attempt, index|
        uri_for_attempt = uri_with_extra_query(uri, attempt[:extra_query])
        response = perform_get(uri_for_attempt, attempt[:headers])
        log_attempt(index: index + 1, uri: uri_for_attempt, headers: attempt[:headers], response: response)
        return response unless missing_subscription_key?(response)

        last_response = response
      end

      last_response || perform_get(uri, build_headers(subscription_key: subscription_key, api_key: api_key))
    end

    def perform_get(uri, headers)
      perform_request(Net::HTTP::Get, uri, headers)
    end

    def perform_post(uri, headers, body)
      perform_request(Net::HTTP::Post, uri, headers, body: body)
    end

    def perform_post_with_fallbacks(uri, body)
      subscription_key = @config[:subscription_key].to_s
      api_key = @config[:api_key].to_s

      attempts = [
        { headers: build_headers(subscription_key: subscription_key, api_key: api_key), extra_query: {} },
        { headers: build_headers(subscription_key: subscription_key, api_key: api_key), extra_query: { "subscription-key" => subscription_key } },
        { headers: build_headers(subscription_key: subscription_key, api_key: api_key), extra_query: { "api-key" => api_key } },
        { headers: build_headers(subscription_key: subscription_key, api_key: api_key), extra_query: { "subscription-key" => subscription_key, "api-key" => api_key } }
      ]

      last_response = nil
      attempts.each_with_index do |attempt, index|
        uri_for_attempt = uri_with_extra_query(uri, attempt[:extra_query])
        response = perform_post(uri_for_attempt, attempt[:headers], body)
        log_attempt(index: index + 1, uri: uri_for_attempt, headers: attempt[:headers], response: response, method: "POST")
        return response unless missing_subscription_key?(response)

        last_response = response
      end

      last_response || perform_post(uri, build_headers(subscription_key: subscription_key, api_key: api_key), body)
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

      body = response.body.to_s.downcase
      body.include?("missing subscription key")
    end

    def uri_with_extra_query(base_uri, extra_query)
      return base_uri if extra_query.blank?

      current = URI.decode_www_form(base_uri.query.to_s)
      extra = extra_query.to_a
      copy = base_uri.dup
      copy.query = URI.encode_www_form(current + extra)
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
      return [] if expected.blank?
      return [] unless payload.is_a?(Array)

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
  end
end
