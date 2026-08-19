# frozen_string_literal: true

# Reporta al CRM una orden ya pagada. Se encola desde el webhook de inscripción (async: el
# usuario ya vio su resultado de pago — regla 8 de crm-gohighlevel).
class CrmReportJob < ApplicationJob
  queue_as :default

  def perform(reference)
    order = OrderRecorder.fetch(reference)
    if order.blank?
      Rails.logger.warn("[GHL] CrmReportJob: no existe la orden #{reference}.")
      return
    end

    Ghl::ReportOrchestrator.report_and_record!(order)
  end
end
