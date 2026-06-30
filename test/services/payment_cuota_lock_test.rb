# frozen_string_literal: true

require "test_helper"

class PaymentCuotaLockTest < ActiveSupport::TestCase
  setup do
    Payment.create!(
      reference: "CLEV-LOCK-1",
      status: "authorized",
      amount: 30.0,
      currency: "USD",
      numero_identificacion: "1102369319",
      consecutivo_credito: 655,
      cuotas: [ "1" ],
      q10_reported: false
    )
  end

  test "blocked_cuotas devuelve cuotas con pago autorizado sin reportar en Q10" do
    assert_equal [ "1" ], PaymentCuotaLock.blocked_cuotas(
      numero_identificacion: "1102369319",
      consecutivo_credito: 655
    )
  end

  test "blocked_cuotas ignora pagos ya reportados en Q10" do
    Payment.find_by!(reference: "CLEV-LOCK-1").update!(q10_reported: true)

    assert_empty PaymentCuotaLock.blocked_cuotas(
      numero_identificacion: "1102369319",
      consecutivo_credito: 655
    )
  end

  test "any_blocked? detecta selección inválida" do
    assert PaymentCuotaLock.any_blocked?(
      numero_identificacion: "1102369319",
      consecutivo_credito: 655,
      cuota_numbers: [ "2", "1" ]
    )
  end
end
