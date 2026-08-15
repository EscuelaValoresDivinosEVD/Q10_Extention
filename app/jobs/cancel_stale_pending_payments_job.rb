# frozen_string_literal: true

class CancelStalePendingPaymentsJob < ApplicationJob
  queue_as :default

  def perform
    cancelled_ids = Payment.cancel_stale_pending!

    Rails.logger.info(
      "[Pagos] Cancelación de pendientes vencidos: #{cancelled_ids.size} pagos " \
      "pasados a cancelado (más de #{Payment.stale_pending_days} días en pendiente)."
    )

    cancelled_ids
  end
end
