# frozen_string_literal: true

module Q10
  class PaymentReporter
    def initialize(client: ApiClient.new, config: Rails.application.config_for(:q10).deep_symbolize_keys)
      @client = client
      @config = config
    end

    def report!(session)
      return { skipped: true, reason: "missing_session" } if session.blank?

      reference = session[:reference]
      return { skipped: true, reason: "already_reported" } if session[:q10_reported]
      return { skipped: true, reason: "missing_credit_context" } unless credit_context?(session)
      return { skipped: true, reason: "missing_codigo_cajero" } if resolve_codigo_cajero(session).blank?

      payload = build_payload(session)
      result = @client.report_pago_credito(payload)
      PaymentSessionStore.mark_q10_reported(reference, response: result)
      result.merge(reported: true)
    end

    private

    def credit_context?(session)
      session[:consecutivo_credito].present? && session[:codigo_persona].present?
    end

    def build_payload(session)
      webhook = normalize_webhook(session[:webhook_payload])

      {
        "Codigo_persona" => session[:codigo_persona].to_s,
        "Codigo_cajero" => resolve_codigo_cajero(session),
        "Consecutivo_credito" => session[:consecutivo_credito].to_i,
        "Fecha_pago" => resolve_fecha_pago(webhook),
        "Formas_pago" => [ build_forma_pago(session, webhook) ],
        "Observacion" => build_observacion(session, webhook)
      }
    end

    def normalize_webhook(payload)
      payload.is_a?(Hash) ? payload.deep_symbolize_keys : {}
    end

    def resolve_codigo_cajero(session)
      session[:codigo_cajero].presence || @config[:codigo_cajero].presence
    end

    def resolve_fecha_pago(webhook)
      raw = webhook[:transactionDate]
      return Time.zone.today.strftime("%Y-%m-%d") if raw.blank?

      Time.zone.parse(raw.to_s).strftime("%Y-%m-%d")
    rescue ArgumentError, TypeError
      Time.zone.today.strftime("%Y-%m-%d")
    end

    def build_forma_pago(session, _webhook)
      {
        "Nombre_cuenta" => @config[:payment_account_name].to_s,
        "Nombre_forma_pago" => @config[:payment_method_name].to_s,
        "Valor" => session[:amount].to_f.round(2)
      }
    end

    def build_observacion(session, webhook)
      parts = [ "Pago CLEV #{session[:reference]}" ]
      cuotas = Array(session[:cuotas]).reject(&:blank?)
      parts << "Cuotas: #{cuotas.join(', ')}" if cuotas.any?

      auth = webhook[:authorizationCode]
      parts << "Auth: #{auth}" if auth.present?

      parts.join(" — ")
    end
  end
end
