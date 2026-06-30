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

  test "GET /admin/pagos muestra conciliación de pagos autorizados sin reportar en Q10" do
    pending_payment = Payment.create!(
      reference: "CLEV-PENDING-Q10",
      status: "authorized",
      amount: 30.0,
      currency: "USD",
      q10_reported: false,
      q10_error: "Reporte omitido: falta código de cajero Q10 (Q10_CODIGO_CAJERO)"
    )

    get admin_payments_path
    assert_response :success
    assert_select "h2", text: /Conciliación Q10/
    assert_select "td", text: pending_payment.reference
    assert_select "td", text: /código de cajero/i
  end

  test "GET /admin/pagos/:id muestra el detalle" do
    get admin_payment_path(@payment)
    assert_response :success
    assert_select "h1", text: /Detalle del pago/
    assert_select "dd", text: @payment.reference
  end

  test "GET /admin/pagos/:id oculta enlace de pago cuando el pago ya está autorizado" do
    @payment.update!(payment_url: "https://payurl.link/test-paid-link")

    get admin_payment_path(@payment)
    assert_response :success
    assert_select "a[href=?]", "https://payurl.link/test-paid-link", count: 0
    assert_select "dd", text: /Enlace deshabilitado/
  end

  test "GET /admin/pagos/:id muestra enlace de pago en intentos pendientes" do
    pending_payment = Payment.create!(
      reference: "CLEV-PENDING-LINK",
      status: "pending",
      amount: 20.0,
      currency: "USD",
      payment_url: "https://payurl.link/test-pending-link"
    )

    get admin_payment_path(pending_payment)
    assert_response :success
    assert_select "a[href=?]", "https://payurl.link/test-pending-link", text: "https://payurl.link/test-pending-link"
  end

  test "GET /admin/pagos/:id con id inexistente responde 404" do
    get admin_payment_path(id: 0)
    assert_response :not_found
  end
end
