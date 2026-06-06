# frozen_string_literal: true

require "test_helper"

class PaymentSessionStoreTest < ActiveSupport::TestCase
  test "save and fetch payment session" do
    PaymentSessionStore.save("REF-1", reference: "REF-1", amount: 50.0, status: "pending")

    session = PaymentSessionStore.fetch("REF-1")
    assert_equal "REF-1", session[:reference]
    assert_equal 50.0, session[:amount]
    assert_equal "pending", session[:status]
  end

  test "update_status changes status and stores webhook payload" do
    PaymentSessionStore.save("REF-2", reference: "REF-2", status: "pending")

    PaymentSessionStore.update_status("REF-2", status: "authorized", webhook_payload: { status: "1" })
    session = PaymentSessionStore.fetch("REF-2")

    assert_equal "authorized", session[:status]
    assert_equal({ status: "1" }, session[:webhook_payload])
  end

  test "mark_q10_reported stores report metadata" do
    PaymentSessionStore.save("REF-3", reference: "REF-3", status: "authorized")

    PaymentSessionStore.mark_q10_reported("REF-3", response: { success: true })
    session = PaymentSessionStore.fetch("REF-3")

    assert session[:q10_reported]
    assert_equal({ success: true }, session[:q10_report_response])
  end
end
