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

  test "successful? solo cuando está authorized" do
    payment = Payment.new(status: "authorized")
    assert payment.successful?

    payment.status = "rejected"
    assert_not payment.successful?
  end
end
