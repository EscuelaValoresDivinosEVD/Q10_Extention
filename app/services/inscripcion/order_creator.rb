# frozen_string_literal: true

module Inscripcion
  # Crea la orden de inscripción y genera el enlace de pago. Concentra las reglas del PRD para que
  # el controller quede fino:
  #
  #   1. el monto NUNCA viene del cliente: sale de PricingSource (regla 1);
  #   2. la disponibilidad se REVALIDA contra Q10 antes de cobrar (regla 4 de catalogo-cursos);
  #   3. la orden se crea `pending` ANTES de llamar a Pagomedios (regla 3): queda rastro del
  #      intento aunque la pasarela falle o la persona abandone;
  #   4. si Pagomedios no devuelve enlace, la orden queda `failed` con el motivo.
  class OrderCreator
    CAMPOS_FACTURACION = %i[
      first_name last_name identification_type_code identification_number
      email phone address city country
    ].freeze

    Resultado = Struct.new(:exito, :order, :payment_url, :error, :motivo, keyword_init: true) do
      def exito? = exito.present?
    end

    def initialize(course_code:, option_code:, billing:, notify_url:, return_url_builder:,
                   catalog: ::Q10::CourseCatalog.new, identification_types: ::Q10::IdentificationTypes.new,
                   gateway: ::PagomediosService)
      @course_code = course_code.to_s
      @option_code = option_code.to_s
      @billing = billing.to_h.symbolize_keys.slice(*CAMPOS_FACTURACION)
      @notify_url = notify_url
      @return_url_builder = return_url_builder
      @catalog = catalog
      @identification_types = identification_types
      @gateway = gateway
    end

    def call
      errores = validar_facturacion
      return fallo(:validacion, errores.first) if errores.any?

      disponibilidad = @catalog.option_snapshot(course_code: @course_code)
      if disponibilidad.blank?
        return fallo(:no_disponible, "Este curso ya no está disponible para inscripción en línea.")
      end

      precio = resolver_precio
      return precio if precio.is_a?(Resultado)

      order = Order.build_from_snapshot(disponibilidad.merge(precio), @billing)
      return fallo(:validacion, order.errors.full_messages.first) unless order.save

      cobrar(order)
    end

    private

    attr_reader :billing

    def resolver_precio
      opcion = PricingSource.snapshot(course_code: @course_code, option_code: @option_code)
      return fallo(:opcion_invalida, "Selecciona una opción de inscripción válida.") if opcion.blank?

      opcion
    rescue PricingSource::NotConfiguredError => e
      # ⛔ Bloqueante conocido: sin fuente de precio no se puede cobrar. Se falla de forma
      # explícita y visible en vez de inventar un monto.
      Rails.logger.error("[Inscripción] #{e.message}")
      fallo(:precio_no_configurado,
            "Las opciones de inscripción de este curso todavía no están disponibles. Escríbenos para ayudarte.")
    end

    def cobrar(order)
      resultado = @gateway.new.create_payment(
        amount: order.amount.to_f,
        currency: order.currency,
        reference: order.reference,
        description: descripcion(order),
        notify_url: @notify_url,
        return_url: @return_url_builder.call(order),
        generate_invoice: 1,   # regla 8: factura electrónica desde el primer pago
        tax_breakdown: {
          amount_with_tax: order.amount_with_tax,
          amount_without_tax: order.amount_without_tax,
          tax_value: order.tax_value
        },
        customer: InvoicePayload.for(order)
      )

      unless resultado[:success]
        mensaje = resultado[:error].presence || "No se pudo generar el enlace de pago."
        OrderRecorder.record_failure!(order, mensaje)
        return fallo(:pagomedios, "No pudimos iniciar el pago. Intenta de nuevo en un momento.", order: order)
      end

      OrderRecorder.record_payment_link!(order, resultado)
      Resultado.new(exito: true, order: order, payment_url: resultado[:payment_url])
    rescue ::PagomediosService::Error => e
      OrderRecorder.record_failure!(order, e.message)
      fallo(:pagomedios, "No pudimos iniciar el pago. Intenta de nuevo en un momento.", order: order)
    end

    def descripcion(order)
      "Inscripción #{order.course_name} — #{order.option_label} (#{order.reference})"
    end

    def validar_facturacion
      errores = []

      CAMPOS_FACTURACION.each do |campo|
        errores << "Completa todos los datos de facturación." if billing[campo].blank?
      end
      return errores.uniq if errores.any?

      errores << "Ingresa un correo válido." unless billing[:email].match?(URI::MailTo::EMAIL_REGEXP)

      unless documento_valido?
        errores << "Revisa tu número de identificación."
      end

      errores
    end

    def documento_valido?
      @identification_types.valid_document?(
        code: billing[:identification_type_code],
        document: billing[:identification_number]
      )
    end

    def fallo(motivo, mensaje, order: nil)
      Resultado.new(exito: false, error: mensaje, motivo: motivo, order: order)
    end
  end
end
