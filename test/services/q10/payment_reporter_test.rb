# frozen_string_literal: true

require "test_helper"

class Q10::PaymentReporterTest < ActiveSupport::TestCase
  setup do
    @attrs = {
      amount: 116.0,
      currency: "USD",
      codigo_persona: "117845823986",
      codigo_cajero: "221367230991",
      consecutivo_credito: 655,
      cuotas: [ "3" ]
    }
    @webhook_payload = {
      status: "1",
      authorizationCode: "243424",
      transactionDate: "2026-03-07 11:06:56",
      cardBrand: "visa"
    }
  end

  test "report! envía payload a Q10 y devuelve éxito" do
    client = Class.new do
      attr_reader :payload

      def report_pago_credito(payload)
        @payload = payload
        { success: true, data: { "ok" => true } }
      end
    end.new

    payment = create_authorized_payment("CLEV-TEST")

    reporter = Q10::PaymentReporter.new(client: client)
    result = reporter.report!(payment)

    assert result[:reported]
    assert_equal "117845823986", client.payload["Codigo_persona"]
    assert_equal "221367230991", client.payload["Codigo_cajero"]
    assert_equal 655, client.payload["Consecutivo_credito"]
    assert_equal "2026-03-07", client.payload["Fecha_pago"]
    assert_equal "Pagosmedios", client.payload["Formas_pago"].first["Nombre_cuenta"]
    assert_equal "Pagosmedios", client.payload["Formas_pago"].first["Nombre_forma_pago"]
    assert_equal 116.0, client.payload["Formas_pago"].first["Valor"]
    assert_match(/CLEV-TEST/, client.payload["Observacion"])
  end

  test "report! omite si ya fue reportado" do
    payment = create_authorized_payment("CLEV-TEST")
    PaymentRecorder.apply_q10_report!(reference: payment.reference, result: { reported: true })

    reporter = Q10::PaymentReporter.new(client: Object.new)
    result = reporter.report!(payment.reload)

    assert_equal "already_reported", result[:reason]
  end

  test "report! omite pagos sin contexto de crédito" do
    PaymentRecorder.record_pending!(
      reference: "CLEV-TEST",
      attrs: @attrs.except(:consecutivo_credito, :codigo_persona)
    )
    payment = PaymentRecorder.fetch("CLEV-TEST")

    reporter = Q10::PaymentReporter.new(client: Object.new)
    result = reporter.report!(payment)

    assert_equal "missing_credit_context", result[:reason]
  end

  private

  def create_authorized_payment(reference)
    PaymentRecorder.record_pending!(reference: reference, attrs: @attrs)
    PaymentRecorder.update_status!(
      reference: reference,
      status: "authorized",
      webhook_payload: @webhook_payload
    )
  end
end
