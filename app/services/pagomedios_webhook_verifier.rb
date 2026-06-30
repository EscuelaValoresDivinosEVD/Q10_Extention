# frozen_string_literal: true

# Valida que las notificaciones servidor de Pagomedios sean confiables antes de
# mutar pagos en la base de datos.
class PagomediosWebhookVerifier
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
  end

  def initialize(request:, payload:)
    @request = request
    @payload = payload.deep_symbolize_keys
  end

  def authenticate!
    verify_webhook_secret!
    verify_payment_binding!
    true
  end

  private

  attr_reader :request, :payload

  def verify_webhook_secret!
    expected = ENV["PAGOMEDIOS_WEBHOOK_SECRET"].to_s
    raise UnauthorizedError, "missing_webhook_secret_config" if expected.blank?

    provided = request.params[:webhook_secret].presence ||
               request.headers["X-Pagomedios-Webhook-Secret"].presence

    return if secure_compare(provided.to_s, expected)

    raise UnauthorizedError, "invalid_webhook_secret"
  end

  def verify_payment_binding!
    reference = notification_reference
    raise UnauthorizedError, "missing_reference" if reference.blank?

    payment = Payment.find_by(reference: reference)
    raise UnauthorizedError, "unknown_payment" if payment.blank?

    verify_amount!(payment)
    verify_idempotent_authorization!(payment)
    payment
  end

  def verify_amount!(payment)
    raw_amount = payload[:amount]
    return if raw_amount.blank?

    webhook_amount = BigDecimal(raw_amount.to_s)
    stored_amount = BigDecimal(payment.amount.to_s)

    return if webhook_amount.round(2) == stored_amount.round(2)

    raise UnauthorizedError, "amount_mismatch"
  rescue ArgumentError
    raise UnauthorizedError, "invalid_amount"
  end

  def verify_idempotent_authorization!(payment)
    return unless payment.successful?

    incoming_auth = payload[:authorizationCode].to_s
    stored_auth = payment.authorization_code.to_s
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
