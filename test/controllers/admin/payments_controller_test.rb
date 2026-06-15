# frozen_string_literal: true

require "test_helper"

class Admin::PaymentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @payment = Payment.create!(
      reference: "CLEV-TEST-001",
      status: "authorized",
      amount: 25.0,
      currency: "USD",
      description: "Pago de prueba",
      numero_identificacion: "1102369319",
      codigo_persona: "119832177599",
      consecutivo_credito: 656,
      cuotas: [ "1" ],
      q10_reported: true
    )
  end

  test "GET /admin/pagos muestra el listado" do
    get admin_payments_path
    assert_response :success
    assert_select "h1", text: /Pagos registrados/
    assert_select "td", text: @payment.reference
  end

  test "GET /admin/pagos/:id muestra el detalle" do
    get admin_payment_path(@payment)
    assert_response :success
    assert_select "h1", text: /Detalle del pago/
    assert_select "dd", text: @payment.reference
  end

  test "GET /admin/pagos/:id con id inexistente responde 404" do
    get admin_payment_path(id: 0)
    assert_response :not_found
  end
end
