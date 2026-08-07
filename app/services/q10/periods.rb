# frozen_string_literal: true

module Q10
  # Catálogo de periodos académicos desde GET /periodos.
  # Por defecto selecciona el periodo del año en curso (ej. Nombre "2026" → Consecutivo 12).
  class Periods
    CACHE_KEY = "q10/periodos/v2"
    CACHE_TTL = 30.minutes

    CONSECUTIVO_FIELDS = %w[Consecutivo Consecutivo_periodo consecutivo].freeze
    NOMBRE_FIELDS = %w[Nombre Nombre_periodo nombre].freeze
    YEAR_FIELDS = %w[Año Anio Year año anio].freeze

    def initialize(client: ApiClient.new, year: Time.zone.now.year)
      @client = client
      @year = year.to_i
    end

    def all
      return fallback_periods unless @client.enabled?

      Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { load_from_api }
    rescue ApiClient::Error => e
      Rails.logger.error("[Q10] Error consultando periodos: #{e.message}")
      fallback_periods
    end

    def options_for_select
      recent.map { |periodo| [ periodo[:name], periodo[:consecutivo] ] }
    end

    # Solo año vigente y año anterior (ej. 2026 y 2025).
    def recent
      allowed_years = [ @year, @year - 1 ]
      matched = all.select { |periodo| allowed_years.include?(periodo[:year].to_i) }
      return matched if matched.any?

      all.first(2)
    end

    def default_consecutivo
      current = find_current_year
      return current[:consecutivo] if current

      recent.first&.dig(:consecutivo).presence || configured_fallback
    end

    def find(consecutivo)
      expected = consecutivo.to_s.strip
      recent.find { |periodo| periodo[:consecutivo].to_s == expected }
    end

    def resolve(consecutivo)
      find(consecutivo)&.dig(:consecutivo).presence || default_consecutivo
    end

    private

    def load_from_api
      result = @client.fetch_periodos(limit: 30, offset: 1)
      normalize_list(result[:data]).presence || fallback_periods
    end

    def normalize_list(payload)
      Array(payload).filter_map do |item|
        next unless item.is_a?(Hash)
        next unless active?(item["Estado"])

        consecutivo = extract_field(item, CONSECUTIVO_FIELDS)
        next if consecutivo.blank?

        name = extract_field(item, NOMBRE_FIELDS).presence || consecutivo.to_s
        {
          consecutivo: consecutivo.to_s,
          name: name.to_s,
          year: extract_year(item, name),
          ordenamiento: item["Ordenamiento"].to_i,
          raw: item
        }
      end.sort_by { |periodo| [ -periodo[:year].to_i, -periodo[:ordenamiento].to_i ] }
    end

    def active?(estado)
      estado == true || estado.to_s.strip.casecmp("verdadero").zero? || estado.to_s.strip.casecmp("true").zero?
    end

    def find_current_year
      all.find { |periodo| periodo[:year] == @year } ||
        all.find { |periodo| periodo[:name].to_s.match?(/\A#{@year}\z/) }
    end

    def extract_field(item, fields)
      fields.each do |field|
        value = item[field]
        return value if value.present?
      end
      nil
    end

    def extract_year(item, name)
      year_value = extract_field(item, YEAR_FIELDS)
      return year_value.to_i if year_value.present? && year_value.to_s.match?(/\A\d{4}\z/)

      match = name.to_s.match(/(20\d{2}|19\d{2})/)
      match ? match[1].to_i : 0
    end

    def configured_fallback
      Rails.application.config_for(:q10).deep_symbolize_keys[:consecutivo_periodo].to_s.presence || "12"
    end

    def fallback_periods
      consecutivo = configured_fallback
      [
        {
          consecutivo: consecutivo,
          name: @year.to_s,
          year: @year,
          ordenamiento: 0,
          raw: {}
        }
      ]
    end
  end
end
