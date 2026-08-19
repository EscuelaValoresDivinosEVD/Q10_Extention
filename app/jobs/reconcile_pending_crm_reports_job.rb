# frozen_string_literal: true

# Barre las órdenes pagadas que aún no llegaron al CRM (webhook perdido, GHL caído, tag fallido)
# y reintenta el reporte. Equivalente de Q10::ReconcilePendingReportsJob para el funnel de
# inscripción; usa el índice parcial `index_orders_crm_pendientes`.
class ReconcilePendingCrmReportsJob < ApplicationJob
  queue_as :default

  def perform
    resultados = Ghl::ReportOrchestrator.reconcile_all_pending!
    reportadas = resultados.count { |entry| entry[:result][:reported] }
    pendientes = resultados.size - reportadas

    Rails.logger.info(
      "[GHL] Conciliación CRM: #{resultados.size} órdenes revisadas, " \
      "#{reportadas} reportadas, #{pendientes} pendientes."
    )
  end
end
