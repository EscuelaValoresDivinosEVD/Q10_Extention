# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Ghl
  # Cliente HTTP de GoHighLevel (LeadConnector). Dos operaciones, contrato confirmado con el
  # OpenAPI oficial:
  #
  #   1. POST /contacts/upsert          → 200, devuelve contact.id / new / traceId
  #   2. POST /contacts/{id}/tags       → 201, aditivo (no pisa los tags previos del contacto)
  #
  # El tag NO se manda en el upsert a propósito: el campo `tags` de ese endpoint SOBRESCRIBE
  # todos los tags del contacto, y quien se inscribe a un segundo curso perdería el tag del
  # primero (ver PRD crm-gohighlevel).
  #
  # Sigue el patrón de Q10::ApiClient: timeouts de config, errores tipados, logging enmascarado.
  class Client
    class Error < StandardError; end
    class UnauthorizedError < Error; end

    def initialize(config: Rails.application.config_for(:ghl).deep_symbolize_keys)
      @config = config
    end

    def enabled?
      @config[:enabled] && token.present? && location_id.present?
    end

    def location_id
      @config[:location_id].to_s.presence
    end

    def source
      @config[:source].to_s.presence
    end

    # Llamada 1 — crea o actualiza el contacto. La deduplicación (por correo/teléfono) la resuelve
    # GoHighLevel según la config de la Location; CLEV no deduplica.
    def upsert_contact(attrs)
      ensure_enabled!

      body = attrs.compact_blank.merge(locationId: location_id)
      response = post("#{base_url}/contacts/upsert", body)
      data = parse_body(response)

      unless response.code.to_i == 200
        raise error_for(response, data, "No se pudo crear/actualizar el contacto en GoHighLevel")
      end

      {
        success: true,
        status: response.code.to_i,
        contact_id: data.dig("contact", "id"),
        new: data["new"],
        trace_id: data["traceId"],
        data: data
      }
    end

    # Llamada 2 — agrega tags al contacto. Aditivo: no pisa los tags existentes. Éxito = 201.
    def add_tags(contact_id:, tags:)
      ensure_enabled!
      raise Error, "contact_id es obligatorio para agregar tags." if contact_id.blank?

      lista = Array(tags).map(&:to_s).compact_blank
      raise Error, "Se requiere al menos un tag." if lista.empty?

      response = post("#{base_url}/contacts/#{contact_id}/tags", { tags: lista })
      data = parse_body(response)

      unless response.code.to_i.in?([ 200, 201 ])
        raise error_for(response, data, "No se pudo aplicar el tag en GoHighLevel")
      end

      { success: true, status: response.code.to_i, tags: data["tags"] || lista, data: data }
    end

    private

    def ensure_enabled!
      return if enabled?

      raise Error, "La integración GoHighLevel está deshabilitada o le falta GHL_TOKEN / GHL_LOCATION_ID."
    end

    def base_url
      @config[:base_url].to_s.chomp("/")
    end

    def token
      @config[:token].to_s.presence
    end

    def api_version
      @config[:api_version].presence || "v3"
    end

    def post(url, body)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = @config[:open_timeout].to_i
      http.read_timeout = @config[:read_timeout].to_i

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Authorization"] = "Bearer #{token}"
      request["Version"] = api_version
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json"
      request.body = body.to_json

      response = http.request(request)
      Rails.logger.info("[GHL] POST #{uri.path} token=#{mask(token)} code=#{response.code}")
      response
    rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError, OpenSSL::SSL::SSLError => e
      raise Error, "No fue posible conectar con GoHighLevel (#{e.class}: #{e.message})."
    end

    def parse_body(response)
      body = response.body.to_s
      return {} if body.blank?

      JSON.parse(body)
    rescue JSON::ParserError
      { "raw" => body.truncate(500) }
    end

    def error_for(response, data, mensaje)
      detalle = data.is_a?(Hash) ? (data["message"] || data["error"] || data.to_json) : data.to_s
      clase = response.code.to_i.in?([ 401, 403 ]) ? UnauthorizedError : Error

      clase.new("#{mensaje} (HTTP #{response.code}): #{detalle.to_s.truncate(300)}")
    end

    def mask(value)
      return "blank" if value.blank?
      return "*" * value.length if value.length <= 8

      "#{value[0, 4]}...#{value[-4, 4]}"
    end
  end
end
