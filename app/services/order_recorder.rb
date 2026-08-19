# frozen_string_literal: true

# Persiste el ciclo de vida de una orden de inscripción: intento → resultado del pago →
# resultado del reporte al CRM. Espejo conceptual de PaymentRecorder (flujo de deudas), con dos
# diferencias deliberadas:
#
#   * guard de monotonía explícito: un webhook tardío no degrada un estado final (ADR-005);
#   * `card_number_masked` se enmascara de verdad antes de persistir (ADR-009) — el recorder de
#     deudas copia el PAN crudo del webhook (hallazgo QA-SEC-01); no se replica ese defecto.
class OrderRecorder
  class << self
    def fetch(reference)
      Order.find_by(reference: reference)
    end

    def fetch_by_return_token(token)
      return nil if token.blank?

      Order.find_by(return_token: token)
    end

    # Guarda el enlace generado por Pagomedios sobre una orden ya creada (regla 3: la orden
    # existe ANTES de ir a la pasarela).
    def record_payment_link!(order, result)
      order.update!(
        pagomedios_token: result[:id],
        payment_url: result[:payment_url],
        error_message: nil
      )
      order
    end

    # La pasarela no devolvió enlace: la orden queda como intento fallido, con el motivo visible
    # en el detalle admin.
    def record_failure!(order, error_message)
      order.update!(status: "failed", error_message: error_message.to_s.truncate(1000))
      order
    end

    def apply_webhook!(reference:, pagomedios_status:, payload: {})
      order = Order.find_by(reference: reference)
      if order.blank?
        Rails.logger.warn("[Inscripción] Webhook sin orden previa para #{reference}; se ignora.")
        return nil
      end

      datos = normalize_hash(payload)
      nuevo_estado = Order::PAGOMEDIOS_STATUS_MAP[pagomedios_status.to_s]

      if nuevo_estado.blank?
        Rails.logger.warn(
          "[Inscripción] Estado desconocido de Pagomedios: #{pagomedios_status} (#{reference}); se conserva #{order.status}."
        )
        nuevo_estado = order.status   # conservador: nunca se asume `paid`
      end

      order.with_lock do
        # Regla 5: un estado final no se degrada por un webhook posterior.
        if order.final? && nuevo_estado != order.status
          Rails.logger.info(
            "[Inscripción] Orden #{reference} ya está #{order.status}; se ignora transición a #{nuevo_estado}."
          )
          return order
        end

        order.update!(
          status: nuevo_estado,
          pagomedios_reference: datos["reference"],
          authorization_code: datos["authorizationCode"],
          card_number_masked: mask_card_number(datos["cardNumber"]),
          card_brand: datos["cardBrand"],
          card_holder: datos["cardHolder"],
          transaction_at: parse_transaction_at(datos["transactionDate"]),
          pagomedios_message: datos["message"],
          # TODO: confirmar el nombre real del campo del número de factura en el webhook de
          # Pagomedios (va junto al pendiente del shape de facturación, ver InvoicePayload).
          # Si no llega con este nombre, la columna queda nula y hay que capturarla de otra forma.
          invoice_number: datos["invoiceNumber"].presence || order.invoice_number,
          pagomedios_payload: datos
        )
      end

      order
    end

    # Espejo de PaymentRecorder.apply_q10_report!, apuntando a GoHighLevel.
    #
    # Escribe con `update_columns` a propósito: el resultado del reporte es auditoría, y debe
    # poder registrarse incluso sobre una orden cuyo contenido resulte inválido (justamente el
    # caso "falta contexto para el tag" que el PRD manda registrar como crm_error). Si dependiera
    # de las validaciones del modelo, el job explotaría en vez de dejar rastro del fallo.
    def apply_crm_report!(reference:, result:)
      order = Order.find_by(reference: reference)
      return if order.blank?

      normalized = normalize_hash(result)

      cambios =
        if normalized["reported"]
          {
            crm_reported: true,
            crm_reported_at: Time.current,
            crm_contact_id: normalized["contact_id"].presence || order.crm_contact_id,
            crm_tag: normalized["tag"].presence || order.crm_tag,
            crm_response: normalize_hash(normalized["response"]),
            crm_error: nil
          }
        else
          {
            crm_contact_id: normalized["contact_id"].presence || order.crm_contact_id,
            crm_response: normalize_hash(normalized["response"]).presence || order.crm_response,
            crm_error: normalized["error"].presence || "Reporte al CRM no completado"
          }
        end

      order.update_columns(cambios.merge(updated_at: Time.current))
      order
    end

    # NUNCA persistir el PAN crudo del webhook (ADR-009).
    def mask_card_number(raw)
      digits = raw.to_s.gsub(/\D/, "")
      return nil if digits.blank?

      "**** **** **** #{digits.last(4)}"
    end

    private

    def normalize_hash(value)
      case value
      when Hash then value.deep_stringify_keys
      when ActionController::Parameters then value.to_unsafe_h.deep_stringify_keys
      else {}
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
