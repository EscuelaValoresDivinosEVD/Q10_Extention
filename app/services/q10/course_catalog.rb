# frozen_string_literal: true

module Q10
  # Disponibilidad de la oferta académica consultada en vivo a Q10 (GET /v1/cursos), con caché
  # corta. No se persiste localmente: Q10 es la fuente de verdad de existencia, cupos, fechas y
  # estado de matrícula (ADR-008). Mismo patrón que Q10::IdentificationTypes, con una diferencia
  # deliberada: acá NO hay fallback con datos — mostrar "disponible" sin confirmarlo sería peor
  # que un estado de error.
  #
  # Q10 no expone precio: `option_snapshot` resuelve disponibilidad, no monto (ver PricingSource).
  class CourseCatalog
    CACHE_KEY = "q10/cursos_disponibles/v1"
    CACHE_TTL = 15.minutes   # más corto que el de IdentificationTypes: los cupos cambian seguido
    ESTADO_ABIERTO = "Abierto"

    attr_reader :error_message

    def initialize(client: ApiClient.new)
      @client = client
      @error_message = nil
    end

    # Lista de ofertas con su disponibilidad. Devuelve [] si Q10 está deshabilitado o si falló
    # y no hay caché vigente; en ese último caso `error?` queda en true para que la vista muestre
    # el estado de error del PRD en vez de un "no encontrado".
    def all
      @error_message = nil
      return [] unless @client.enabled?

      Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { load_from_api }
    rescue ApiClient::Error => e
      Rails.logger.error("[Q10] Error consultando disponibilidad de cursos: #{e.message}")
      cacheados = Rails.cache.read(CACHE_KEY)
      @error_message = e.message if cacheados.blank?
      cacheados || []
    end

    # true solo si la última consulta falló y tampoco había caché para servir.
    def error? = @error_message.present?

    def deshabilitado? = !@client.enabled?

    def find_by_code(course_code)
      return nil if course_code.blank?

      all.find { |curso| curso[:code] == course_code.to_s }
    end

    # Cupos que quedan disponibles para inscribirse.
    def cupos_disponibles(curso)
      return 0 if curso.blank?

      [ curso[:cupo_maximo].to_i - curso[:matriculados].to_i, 0 ].max
    end

    def cupos?(curso)
      curso.present? && curso[:cupo_maximo].to_i > curso[:matriculados].to_i
    end

    # Regla 1 de catalogo-cursos: visible solo si Q10 lo tiene abierto y admite matrícula en línea.
    def visible?(curso)
      curso.present? && curso[:estado] == ESTADO_ABIERTO && curso[:aplica_matricula_en_linea]
    end

    # Reglas 1 y 2: pagable solo si además tiene cupos.
    def disponible?(curso)
      visible?(curso) && cupos?(curso)
    end

    # Revalida DISPONIBILIDAD contra Q10 antes de crear una orden (regla 4 de catalogo-cursos).
    # Devuelve nil si el curso no existe, está cerrado, no admite matrícula en línea o no tiene cupos.
    #
    # NOTA: no incluye `amount`/`option_code`/`option_label` — Q10 no expone precio ni opciones de
    # inscripción. Esa mitad del snapshot la aporta Inscripcion::PricingSource (hoy sin fuente
    # definida). No completar acá con valores inventados.
    def option_snapshot(course_code:)
      curso = find_by_code(course_code)
      return nil unless disponible?(curso)

      {
        course_code: curso[:code],
        course_name: curso[:name],
        course_edition_year: curso[:edition_year],
        tax_rate: 0.0   # IVA 0% fijo: cursos = servicios educativos exentos (ADR-004)
      }
    end

    private

    def load_from_api
      result = @client.fetch_cursos_disponibles(limit: 50, offset: 1)
      normalize_list(result[:data])
    end

    # Mapeo del contrato real de Q10 (ver diccionario-datos.md §1). Se ignoran deliberadamente
    # los datos de docente/programa/asignatura/pensum (fuera de alcance de un checkout) y los
    # campos de descuento (fuera de alcance explícito del PRD).
    def normalize_list(payload)
      Array(payload).filter_map do |curso|
        next unless curso.is_a?(Hash)

        codigo = curso["Codigo"].to_s
        next if codigo.blank?

        {
          code: codigo,
          name: curso["Nombre"].to_s,
          estado: curso["Estado"].to_s,
          aplica_matricula_en_linea: curso["Aplica_matricula_en_linea"] == true,
          cupo_maximo: curso["Cupo_maximo"].to_i,
          matriculados: curso["Cantidad_estudiantes_matriculados"].to_i,
          edition_year: parse_edition_year(curso["Fecha_inicio"]),
          fecha_inicio: parse_fecha(curso["Fecha_inicio"]),
          fecha_fin: parse_fecha(curso["Fecha_fin"])
        }
      end
    end

    def parse_edition_year(fecha_inicio)
      parse_fecha(fecha_inicio)&.year
    end

    def parse_fecha(valor)
      return nil if valor.blank?

      Time.zone.parse(valor.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
