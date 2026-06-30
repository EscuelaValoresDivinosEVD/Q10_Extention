# frozen_string_literal: true

require "test_helper"

class Q10::ReportOrchestratorReconcileTest < ActiveSupport::TestCase
  setup do
    @payment = Payment.create!(
      reference: "CLEV-RECONCILE",
      status: "authorized",
      amount: 30.0,
      currency: "USD",
      numero_identificacion: "1102369319",
      codigo_persona: "117845823986",
      codigo_cajero: "221367230991",
      consecutivo_credito: 655,
      cuotas: [ "1" ],
      q10_reported: false,
      pagomedios_payload: { "authorizationCode" => "123456" }
    )
  end

  test "reconcile_all_pending! reporta pagos pendientes" do
    original_report = Q10::PaymentReporter.instance_method(:report!)
    Q10::PaymentReporter.define_method(:report!) { |payment| { reported: true, reference: payment.reference } }

    results = Q10::ReportOrchestrator.reconcile_all_pending!
    assert_equal 1, results.size
    assert results.first[:result][:reported]
    assert @payment.reload.q10_reported
  ensure
    Q10::PaymentReporter.define_method(:report!, original_report)
  end
end
