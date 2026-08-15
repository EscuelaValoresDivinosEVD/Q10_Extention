# frozen_string_literal: true

require "test_helper"

class PaymentTest < ActiveSupport::TestCase
  test "valida referencia única y estados permitidos" do
    payment = Payment.new(
      reference: "CLEV-TEST-1",
      status: "pending",
      amount: 30,
      currency: "USD"
    )
    assert payment.valid?

    payment.status = "invalid"
    assert_not payment.valid?
  end

  test "created_between filtra por created_at" do
    old_payment = Payment.create!(
      reference: "CLEV-SCOPE-OLD",
      status: "pending",
      amount: 5,
      currency: "USD",
      created_at: 8.days.ago
    )
    recent_payment = Payment.create!(
      reference: "CLEV-SCOPE-NEW",
      status: "pending",
      amount: 6,
      currency: "USD",
      created_at: 1.day.ago
    )

    results = Payment.created_between(3.days.ago.to_date, Date.current)

    assert_includes results, recent_payment
    assert_not_includes results, old_payment
  end

  test "cancel_stale_pending! pasa a cancelado los pendientes según PAYMENT_STALE_PENDING_DAYS" do
    previous = ENV["PAYMENT_STALE_PENDING_DAYS"]
    ENV["PAYMENT_STALE_PENDING_DAYS"] = "7"

    stale = Payment.create!(
      reference: "CLEV-STALE-PENDING",
      status: "pending",
      amount: 10,
      currency: "USD",
      created_at: 8.days.ago
    )
    fresh = Payment.create!(
      reference: "CLEV-FRESH-PENDING",
      status: "pending",
      amount: 11,
      currency: "USD",
      created_at: 3.days.ago
    )
    authorized = Payment.create!(
      reference: "CLEV-OLD-AUTHORIZED",
      status: "authorized",
      amount: 12,
      currency: "USD",
      created_at: 10.days.ago,
      q10_reported: true
    )

    cancelled_ids = Payment.cancel_stale_pending!

    assert_includes cancelled_ids, stale.id
    assert_equal "cancelled", stale.reload.status
    assert_equal "pending", fresh.reload.status
    assert_equal "authorized", authorized.reload.status
  ensure
    if previous.nil?
      ENV.delete("PAYMENT_STALE_PENDING_DAYS")
    else
      ENV["PAYMENT_STALE_PENDING_DAYS"] = previous
    end
  end

  test "stale_pending_days usa la variable de entorno y cae al default si es inválida" do
    previous = ENV["PAYMENT_STALE_PENDING_DAYS"]

    ENV["PAYMENT_STALE_PENDING_DAYS"] = "10"
    assert_equal 10, Payment.stale_pending_days
    assert_equal 10.days, Payment.stale_pending_after

    ENV["PAYMENT_STALE_PENDING_DAYS"] = "0"
    assert_equal Payment::DEFAULT_STALE_PENDING_DAYS, Payment.stale_pending_days
  ensure
    if previous.nil?
      ENV.delete("PAYMENT_STALE_PENDING_DAYS")
    else
      ENV["PAYMENT_STALE_PENDING_DAYS"] = previous
    end
  end
end
