# frozen_string_literal: true

require "test_helper"

class Q10::PaymentReporterTest < ActiveSupport::TestCase
  setup do
    @session = {
      reference: "CLEV-TEST",
      status: "authorized",
      amount: 116.0,
      codigo_persona: "117845823986",
      codigo_cajero: "221367230991",
      consecutivo_credito: 655,
      cuotas: [ "3" ],
      webhook_payload: {
        status: "1",
        authorizationCode: "243424",
        transactionDate: "2026-03-07 11:06:56",
        cardBrand: "visa"
      }
    }
  end

  test "report! envía payload a Q10 y marca sesión como reportada" do
    client = Class.new do
      attr_reader :payload

      def report_pago_credito(payload)
        @payload = payload
        { success: true, data: { "ok" => true } }
      end
    end.new

    PaymentSessionStore.save("CLEV-TEST", @session)

    reporter = Q10::PaymentReporter.new(client: client)
    result = reporter.report!(PaymentSessionStore.fetch("CLEV-TEST"))

    assert result[:reported]
    assert_equal "117845823986", client.payload["Codigo_persona"]
    assert_equal "221367230991", client.payload["Codigo_cajero"]
    assert_equal 655, client.payload["Consecutivo_credito"]
    assert_equal "2026-03-07", client.payload["Fecha_pago"]
    assert_equal "Pagosmedios", client.payload["Formas_pago"].first["Nombre_cuenta"]
    assert_equal "Pagosmedios", client.payload["Formas_pago"].first["Nombre_forma_pago"]
    assert_equal 116.0, client.payload["Formas_pago"].first["Valor"]
    assert_match(/CLEV-TEST/, client.payload["Observacion"])

    session = PaymentSessionStore.fetch("CLEV-TEST")
    assert session[:q10_reported]
  end

  test "report! omite si ya fue reportado" do
    PaymentSessionStore.save("CLEV-TEST", @session.merge(q10_reported: true))

    reporter = Q10::PaymentReporter.new(client: Object.new)
    result = reporter.report!(PaymentSessionStore.fetch("CLEV-TEST"))

    assert_equal "already_reported", result[:reason]
  end

  test "report! omite pagos sin contexto de crédito" do
    PaymentSessionStore.save("CLEV-TEST", @session.except(:consecutivo_credito, :codigo_persona))

    reporter = Q10::PaymentReporter.new(client: Object.new)
    result = reporter.report!(PaymentSessionStore.fetch("CLEV-TEST"))

    assert_equal "missing_credit_context", result[:reason]
  end
end
