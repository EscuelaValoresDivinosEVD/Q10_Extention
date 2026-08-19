# frozen_string_literal: true

module Inscripcion
  # Valida las notificaciones de Pagomedios del funnel de inscripción antes de mutar una orden.
  #
  # Es un espejo de PagomediosWebhookVerifier (flujo de deudas) y NO lo reutiliza porque aquel
  # está atado al modelo `Payment` (`Payment.find_by(reference:)` → `unknown_payment`) y al
  # secreto `PAGOMEDIOS_WEBHOOK_SECRET`: usarlo tal cual rechazaría toda orden `INSC-`, y
  # modificarlo tocaría código en producción del cobro de deudas (ADR-011: el funnel es aditivo).
  # Lo que se reutiliza es el patrón: secreto en el path + binding contra el registro + guard de
  # autorización idempotente.
  class WebhookVerifier
    class UnauthorizedError < StandardError
      attr_reader :reason

      def initialize(reason)
        @reason = reason
        super(reason.to_s)
      end
    end

    class << self
      def authenticate!(request:, payload:)
        new(request: request, payload: payload).authenticate!
      end

      def secret
        ENV["INSCRIPCION_WEBHOOK_SECRET"].to_s
      end
    end

    def initialize(request:, payload:)
      @request = request
      @payload = payload.deep_symbolize_keys
    end

    def authenticate!
      verify_webhook_secret!
      verify_order_binding!
    end

    private

    attr_reader :request, :payload

    def verify_webhook_secret!
      expected = self.class.secret
      raise UnauthorizedError, "missing_webhook_secret_config" if expected.blank?

      provided = request.params[:webhook_secret].presence ||
                 request.headers["X-Pagomedios-Webhook-Secret"].presence

      return if secure_compare(provided.to_s, expected)

      raise UnauthorizedError, "invalid_webhook_secret"
    end

    def verify_order_binding!
      reference = notification_reference
      raise UnauthorizedError, "missing_reference" if reference.blank?

      order = Order.find_by(reference: reference)
      raise UnauthorizedError, "unknown_order" if order.blank?

      verify_amount!(order)
      verify_idempotent_authorization!(order)
      order
    end

    def verify_amount!(order)
      raw_amount = payload[:amount]
      return if raw_amount.blank?

      webhook_amount = BigDecimal(raw_amount.to_s)
      stored_amount = BigDecimal(order.amount.to_s)

      return if webhook_amount.round(2) == stored_amount.round(2)

      raise UnauthorizedError, "amount_mismatch"
    rescue ArgumentError
      raise UnauthorizedError, "invalid_amount"
    end

    def verify_idempotent_authorization!(order)
      return unless order.pagada?

      incoming_auth = payload[:authorizationCode].to_s
      stored_auth = order.authorization_code.to_s
      return if incoming_auth.blank? || stored_auth.blank?
      return if secure_compare(incoming_auth, stored_auth)

      raise UnauthorizedError, "conflicting_authorization"
    end

    def notification_reference
      payload[:customValue].presence || payload[:reference].presence
    end

    def secure_compare(given, expected)
      ActiveSupport::SecurityUtils.secure_compare(given, expected)
    rescue ArgumentError
      false
    end
  end
end
