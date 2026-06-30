# frozen_string_literal: true

module Q10
  class ReconcilePendingReportsJob < ApplicationJob
    queue_as :default

    def perform
      results = ReportOrchestrator.reconcile_all_pending!
      reported = results.count { |entry| entry[:result][:reported] }
      pending = results.size - reported

      Rails.logger.info(
        "[Q10] Conciliación diaria: #{results.size} pagos revisados, " \
        "#{reported} reportados, #{pending} pendientes."
      )
    end
  end
end
