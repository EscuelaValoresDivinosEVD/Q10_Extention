# frozen_string_literal: true

require "test_helper"

class CancelStalePendingPaymentsJobTest < ActiveJob::TestCase
  test "cancela pagos pendientes vencidos" do
    stale = Payment.create!(
      reference: "CLEV-JOB-STALE",
      status: "pending",
      amount: 20,
      currency: "USD",
      created_at: 9.days.ago
    )

    cancelled_ids = CancelStalePendingPaymentsJob.perform_now

    assert_includes cancelled_ids, stale.id
    assert_equal "cancelled", stale.reload.status
  end
end
