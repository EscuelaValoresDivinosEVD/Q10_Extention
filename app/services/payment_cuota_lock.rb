# frozen_string_literal: true

# Cuotas con pago autorizado en Pagomedios pero aún sin reporte exitoso en Q10.
class PaymentCuotaLock
  class << self
    def blocked_cuotas(numero_identificacion:, consecutivo_credito:)
      return [] if numero_identificacion.blank? || consecutivo_credito.blank?

      Payment.q10_pending_report
        .where(numero_identificacion: numero_identificacion.to_s.strip, consecutivo_credito: consecutivo_credito.to_i)
        .flat_map { |payment| Array(payment.cuotas) }
        .map { |cuota| cuota.to_s.strip }
        .reject(&:blank?)
        .uniq
    end

    def blocked_cuotas_by_credit(numero_identificacion:)
      return {} if numero_identificacion.blank?

      Payment.q10_pending_report
        .where(numero_identificacion: numero_identificacion.to_s.strip)
        .where.not(consecutivo_credito: nil)
        .group_by(&:consecutivo_credito)
        .transform_values do |payments|
          payments.flat_map { |payment| Array(payment.cuotas) }
            .map { |cuota| cuota.to_s.strip }
            .reject(&:blank?)
            .uniq
        end
    end

    def blocked?(numero_identificacion:, consecutivo_credito:, cuota_numero:)
      blocked_cuotas(
        numero_identificacion: numero_identificacion,
        consecutivo_credito: consecutivo_credito
      ).include?(cuota_numero.to_s)
    end

    def any_blocked?(numero_identificacion:, consecutivo_credito:, cuota_numbers:)
      blocked = blocked_cuotas(
        numero_identificacion: numero_identificacion,
        consecutivo_credito: consecutivo_credito
      )
      Array(cuota_numbers).map(&:to_s).any? { |cuota| blocked.include?(cuota) }
    end
  end
end
