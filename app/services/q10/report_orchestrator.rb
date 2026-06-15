# frozen_string_literal: true

module Q10
  class ReportOrchestrator
    class << self
      def report_and_record!(session)
        reference = session[:reference]
        result = PaymentReporter.new.report!(session)
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
        session = PaymentSessionStore.fetch(reference)
        return false if session.blank? || session[:q10_reported] || session[:status] != "authorized"

        report_and_record!(session)[:reported]
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
