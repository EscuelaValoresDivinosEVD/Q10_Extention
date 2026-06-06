# frozen_string_literal: true

# Almacena en caché el contexto de un pago pendiente hasta que Pagomedios confirme vía webhook.
# Más adelante se usará para reportar el abono en Q10.
class PaymentSessionStore
  TTL = 7.days

  class << self
    def save(reference, data)
      Rails.cache.write(cache_key(reference), data.deep_stringify_keys, expires_in: TTL)
    end

    def fetch(reference)
      data = Rails.cache.read(cache_key(reference))
      data&.deep_symbolize_keys
    end

    def update_status(reference, status:, webhook_payload: {})
      data = fetch(reference) || { reference: reference }
      data[:status] = status
      data[:webhook_payload] = webhook_payload
      data[:updated_at] = Time.current.iso8601
      save(reference, data)
      data
    end

    def mark_q10_reported(reference, response: {})
      data = fetch(reference) || { reference: reference }
      data[:q10_reported] = true
      data[:q10_report_response] = response
      data[:q10_reported_at] = Time.current.iso8601
      save(reference, data)
      data
    end

    private

    def cache_key(reference)
      "payment_session:#{reference}"
    end
  end
end
