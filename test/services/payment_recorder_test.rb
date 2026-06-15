# frozen_string_literal: true

require "test_helper"

class PaymentRecorderTest < ActiveSupport::TestCase
  setup do
    @attrs = {
      amount: 29.0,
      currency: "USD",
      description: "Pago cuota 1",
      numero_identificacion: "1102369319",
      codigo_persona: "119832177599",
      codigo_cajero: "221367230991",
      consecutivo_credito: 657,
      cuotas: [ "1" ],
      pagomedios_token: "token-abc",
      payment_url: "https://pay.example.com/1",
      return_token: "token-panel"
    }
  end

  test "record_pending! crea intento pendiente" do
    payment = PaymentRecorder.record_pending!(reference: "CLEV-PENDING", attrs: @attrs)

    assert_equal "pending", payment.status
    assert_equal 29.0, payment.amount.to_f
    assert_equal [ "1" ], payment.cuotas
  end

  test "record_failed! guarda error de intento fallido" do
    payment = PaymentRecorder.record_failed!(
      reference: "CLEV-FAIL",
      attrs: @attrs,
      error_message: "Pagomedios API error 400"
    )

    assert_equal "failed", payment.status
    assert_equal "Pagomedios API error 400", payment.error_message
  end

  test "apply_webhook! actualiza detalle de Pagomedios" do
    PaymentRecorder.record_pending!(reference: "CLEV-WH", attrs: @attrs)

    PaymentRecorder.apply_webhook!(
      reference: "CLEV-WH",
      status: "authorized",
      webhook_payload: {
        status: "1",
        reference: "LP-123",
        authorizationCode: "864936",
        cardNumber: "420000******0000",
        cardBrand: "visa",
        cardHolder: "Cesar Prueba",
        transactionDate: "2026-06-06 07:55:56",
        message: "Transaccion aprobada"
      }
    )

    payment = Payment.find_by!(reference: "CLEV-WH")
    assert_equal "authorized", payment.status
    assert_equal "LP-123", payment.pagomedios_reference
    assert_equal "864936", payment.authorization_code
    assert_equal "visa", payment.card_brand
  end

  test "apply_q10_report! marca reporte exitoso" do
    PaymentRecorder.record_pending!(reference: "CLEV-Q10", attrs: @attrs)

    PaymentRecorder.apply_q10_report!(
      reference: "CLEV-Q10",
      result: { reported: true, data: { "code" => "200" } }
    )

    payment = Payment.find_by!(reference: "CLEV-Q10")
    assert payment.q10_reported
    assert_not_nil payment.q10_reported_at
  end
end
