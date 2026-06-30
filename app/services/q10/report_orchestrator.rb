# frozen_string_literal: true

module Q10
  class ReportOrchestrator
    class << self
      def report_and_record!(payment)
        reference = payment.reference
        result = PaymentReporter.new.report!(payment)
        log_result(reference, result)
        PaymentRecorder.apply_q10_report!(reference: reference, result: result)
        result
      rescue ApiClient::Error => e
        Rails.logger.error("[Q10] No se pudo reportar pago #{reference}: #{e.message}")
        result = { reported: false, error: e.message }
        PaymentRecorder.apply_q10_report!(reference: reference, result: result)
        result
      end

      def retry_report!(reference)
        payment = PaymentRecorder.fetch(reference)
        return false if payment.blank? || payment.q10_reported? || payment.status != "authorized"

        report_and_record!(payment)[:reported]
      end

      def reconcile_all_pending!(scope: Payment.q10_pending_report)
        scope.order(:created_at).map do |payment|
          { reference: payment.reference, result: report_and_record!(payment) }
        end
      end

      def reconcile_for_student!(numero_identificacion:)
        reconcile_all_pending!(
          scope: Payment.q10_pending_report.where(numero_identificacion: numero_identificacion.to_s.strip)
        )
      end

      private

      def log_result(reference, result)
        if result[:reported]
          Rails.logger.info("[Q10] Pago #{reference} reportado correctamente.")
        elsif result[:skipped]
          Rails.logger.info("[Q10] Reporte omitido para #{reference}: #{result[:reason]}")
        end
      end
    end
  end
end
