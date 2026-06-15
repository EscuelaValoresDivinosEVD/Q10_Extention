# frozen_string_literal: true

module Q10
  class IdentificationTypes
    CACHE_KEY = "q10/tipos_identificacion/v1"
    CACHE_TTL = 1.hour

    def initialize(client: ApiClient.new)
      @client = client
    end

    def all
      return fallback_types unless @client.enabled?

      Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) do
        load_from_api
      end
    rescue ApiClient::Error => e
      Rails.logger.error("[Q10] Error consultando tipos de identificación: #{e.message}")
      fallback_types
    end

    def find_by_code(code)
      all.find { |tipo| tipo[:code] == code.to_s }
    end

    def valid_document?(code:, document:)
      tipo = find_by_code(code)
      return false if tipo.blank?

      pattern = tipo[:pattern]
      return true if pattern.blank?

      Regexp.new(pattern).match?(document.to_s.strip)
    rescue RegexpError => e
      Rails.logger.warn("[Q10] Expresión regular inválida para #{code}: #{e.message}")
      true
    end

    private

    def load_from_api
      result = @client.fetch_tipos_identificacion(limit: 30, offset: 1)
      normalize_list(result[:data]).presence || fallback_types
    end

    def normalize_list(payload)
      Array(payload).filter_map do |item|
        next unless item.is_a?(Hash)
        next unless active?(item["Estado"])

        code = item["Código"].presence || item["Codigo"].presence
        next if code.blank?

        {
          code: code.to_s,
          name: item["Nombre"].to_s,
          abbreviation: item["Abreviatura"].to_s,
          pattern: item["ExpresiónRegular"].presence || item["ExpresionRegular"].presence
        }
      end
    end

    def active?(estado)
      estado == true || estado.to_s.strip.casecmp("verdadero").zero?
    end

    def fallback_types
      FALLBACK_TYPES
    end

    FALLBACK_TYPES = [
      { code: "EC01", name: "Cédula de identidad", abbreviation: "CI", pattern: '^\d{10}$' },
      { code: "68", name: "Cédula de identidad para extranjeros", abbreviation: "CIE", pattern: "^[a-zA-Z0-9_]{4,16}$" },
      { code: "EC03", name: "Pasaporte", abbreviation: "PP", pattern: "^[a-zA-Z0-9_]{4,16}$" },
      { code: "EC09", name: "Carné de refugio", abbreviation: "CR", pattern: "^[a-zA-Z0-9_]{4,16}$" },
      { code: "EC05", name: "Registro único de contribuyentes", abbreviation: "RUC", pattern: '^\d{13}$' }
    ].freeze
  end
end
