# frozen_string_literal: true

# Persiste el ciclo completo del pago en la base de datos desde el inicio del intento.
class PaymentRecorder
  class << self
    def fetch(reference)
      Payment.find_by(reference: reference)
    end

    def record_pending!(reference:, attrs:)
      upsert_payment(reference, attrs.merge(status: "pending"))
    end

    def record_failed!(reference:, attrs:, error_message:)
      upsert_payment(reference, attrs.merge(status: "failed", error_message: error_message))
    end

    def update_status!(reference:, status:, webhook_payload: {})
      apply_webhook!(reference: reference, status: status, webhook_payload: webhook_payload)
      fetch(reference)
    end

    def apply_webhook!(reference:, status:, webhook_payload:)
      payment = Payment.find_by(reference: reference)
      return if payment.blank?

      payload = normalize_hash(webhook_payload)
      payment.update!(
        status: status,
        pagomedios_reference: payload["reference"],
        authorization_code: payload["authorizationCode"],
        card_number_masked: payload["cardNumber"],
        card_brand: payload["cardBrand"],
        card_holder: payload["cardHolder"],
        transaction_at: parse_transaction_at(payload["transactionDate"]),
        pagomedios_message: payload["message"],
        pagomedios_payload: payload
      )
    end

    def apply_q10_report!(reference:, result:)
      payment = Payment.find_by(reference: reference)
      return if payment.blank?

      normalized = normalize_hash(result)

      if normalized["reported"]
        payment.update!(
          q10_reported: true,
          q10_reported_at: Time.current,
          q10_response: normalized,
          q10_error: nil
        )
      else
        payment.update!(
          q10_response: normalized,
          q10_error: q10_report_failure_message(normalized)
        )
      end
    end

    def q10_report_failure_message(result)
      if result["error"].present?
        result["error"].to_s
      elsif result["skipped"] && result["reason"].present?
        "Reporte omitido: #{q10_skip_reason_label(result['reason'])}"
      end
    end

    def q10_skip_reason_label(reason)
      {
        "already_reported" => "ya reportado previamente",
        "missing_payment" => "pago no encontrado en la base de datos",
        "missing_credit_context" => "falta contexto de crédito (persona o consecutivo)",
        "missing_codigo_cajero" => "falta código de cajero Q10 (Q10_CODIGO_CAJERO)"
      }.fetch(reason.to_s, reason.to_s.humanize)
    end

    private

    def upsert_payment(reference, attrs)
      payment = Payment.find_or_initialize_by(reference: reference)
      payment.assign_attributes(attrs)
      payment.save!
      payment
    end

    def normalize_hash(value)
      case value
      when Hash
        value.deep_stringify_keys
      else
        {}
      end
    end

    def parse_transaction_at(raw)
      return if raw.blank?

      Time.zone.parse(raw.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
