# frozen_string_literal: true

module Inscripcion
  # ⛔ PIEZA BLOQUEADA — fuente del precio de las opciones de inscripción.
  #
  # Q10 expone disponibilidad, NO precio (contrato real confirmado 2026-07-21). De dónde sale el
  # monto de "reserva / pago parcial / pago completo" es la única decisión de producto que sigue
  # abierta, y bloquea el `create` del checkout.
  #
  # Este service aísla esa decisión detrás de una interfaz estable: hoy lee `config/inscripcion_
  # pricing.yml`, que viene VACÍO a propósito. Mientras no haya opciones configuradas:
  #
  #   * `opciones(course_code:)` devuelve [] → el checkout muestra el aviso de "opciones no
  #     disponibles" en vez de una lista de precios inventada;
  #   * `snapshot(...)` levanta NotConfiguredError → es imposible crear una orden o llamar a
  #     Pagomedios.
  #
  # Cuando el cliente defina la fuente, se reemplaza SOLO la implementación de `catalogo`
  # (config, endpoint nuevo de Q10, parámetro firmado del sitio externo…). Nada más cambia.
  class PricingSource
    class NotConfiguredError < StandardError; end

    KINDS = %w[reserva parcial completo].freeze

    class << self
      # Opciones de inscripción disponibles para un curso. [] mientras no haya fuente definida.
      def opciones(course_code:)
        return [] if course_code.blank?

        listado = catalogo[course_code.to_s] || catalogo[course_code.to_s.upcase] || []
        Array(listado).filter_map { |opcion| normalizar(opcion) }
      end

      def configurado?(course_code:)
        opciones(course_code: course_code).any?
      end

      # Mitad "comercial" del snapshot de la orden (la otra mitad —disponibilidad— la aporta
      # Q10::CourseCatalog#option_snapshot). El monto SIEMPRE sale de acá, nunca del request:
      # regla 1 de checkout-inscripcion.
      def snapshot(course_code:, option_code:)
        disponibles = opciones(course_code: course_code)

        if disponibles.empty?
          raise NotConfiguredError,
                "No hay opciones de inscripción configuradas para el curso #{course_code}: " \
                "falta definir la fuente del precio (ver config/inscripcion_pricing.yml)."
        end

        disponibles.find { |opcion| opcion[:option_code] == option_code.to_s }
      end

      private

      def catalogo
        config = Rails.application.config_for(:inscripcion_pricing)
        cursos = config[:cursos] || config["cursos"] || {}
        cursos.deep_stringify_keys
      rescue StandardError => e
        Rails.logger.error("[Inscripción] No se pudo leer la configuración de precios: #{e.message}")
        {}
      end

      def normalizar(opcion)
        datos = opcion.deep_symbolize_keys
        codigo = datos[:codigo].to_s
        monto = datos[:monto]
        return nil if codigo.blank? || monto.blank?

        {
          option_code: codigo,
          option_kind: kind_valido(datos[:tipo]),
          option_label: datos[:etiqueta].presence || codigo.humanize,
          amount: BigDecimal(monto.to_s),
          currency: datos[:moneda].presence || "USD",
          tax_rate: 0.0   # IVA 0% fijo (ADR-004) — no configurable por opción
        }
      rescue ArgumentError, TypeError => e
        Rails.logger.error("[Inscripción] Opción de precio inválida (#{opcion.inspect}): #{e.message}")
        nil
      end

      def kind_valido(tipo)
        valor = tipo.to_s.downcase
        KINDS.include?(valor) ? valor : "completo"
      end
    end
  end
end
