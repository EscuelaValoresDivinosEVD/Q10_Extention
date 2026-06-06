# frozen_string_literal: true

class PaymentRecorder
  class << self
    def record_pending!(reference:, attrs:)
      upsert_payment(reference, attrs.merge(status: "pending"))
    end

    def record_failed!(reference:, attrs:, error_message:)
      upsert_payment(reference, attrs.merge(status: "failed", error_message: error_message))
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

      if result[:reported]
        payment.update!(
          q10_reported: true,
          q10_reported_at: Time.current,
          q10_response: normalize_hash(result),
          q10_error: nil
        )
      elsif result[:error].present?
        payment.update!(q10_error: result[:error].to_s)
      end
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
