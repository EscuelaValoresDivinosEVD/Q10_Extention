# frozen_string_literal: true

require "test_helper"

class Admin::PaymentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @previous_admin_password = ENV["ADMIN_PASSWORD"]
    ENV.delete("ADMIN_PASSWORD")

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

  teardown do
    if @previous_admin_password.nil?
      ENV.delete("ADMIN_PASSWORD")
    else
      ENV["ADMIN_PASSWORD"] = @previous_admin_password
    end
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
    @payment.update!(nombre: "Carlos", apellido: "Bedoya")

    get admin_payment_path(@payment)
    assert_response :success
    assert_select "h1", text: /Detalle del pago/
    assert_select "dd", text: @payment.reference
    assert_select "dt", text: "Nombre"
    assert_select "dd", text: "Carlos"
    assert_select "dt", text: "Apellido"
    assert_select "dd", text: "Bedoya"
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

  test "GET /admin/pagos filtra por rango de fechas" do
    old_payment = Payment.create!(
      reference: "CLEV-OLD-001",
      status: "pending",
      amount: 10.0,
      currency: "USD",
      created_at: 10.days.ago
    )
    recent_payment = Payment.create!(
      reference: "CLEV-RECENT-001",
      status: "pending",
      amount: 12.0,
      currency: "USD",
      created_at: 1.day.ago
    )

    get admin_payments_path, params: {
      fecha_desde: 3.days.ago.to_date,
      fecha_hasta: Date.current
    }

    assert_response :success
    assert_select "td", text: recent_payment.reference
    assert_select "td", text: old_payment.reference, count: 0
    assert_select "input[name=fecha_desde]"
    assert_select "a", text: "Exportar a Excel"
  end

  test "GET /admin/pagos/exportar descarga un Excel con los pagos filtrados" do
    old_payment = Payment.create!(
      reference: "CLEV-EXPORT-OLD",
      status: "pending",
      amount: 8.0,
      currency: "USD",
      created_at: 20.days.ago
    )
    included = Payment.create!(
      reference: "CLEV-EXPORT-OK",
      status: "authorized",
      amount: 15.0,
      currency: "USD",
      created_at: 2.days.ago,
      q10_reported: true
    )

    filtered = Payment.created_between(5.days.ago.to_date, Date.current)
    assert_includes filtered, included
    assert_not_includes filtered, old_payment

    get export_admin_payments_path, params: {
      fecha_desde: 5.days.ago.to_date,
      fecha_hasta: Date.current
    }

    assert_response :success
    assert_equal "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", response.media_type
    assert_match(/pagos_clev_.*\.xlsx/, response.headers["Content-Disposition"])
    assert_equal "PK", response.body[0, 2]
    assert_operator response.body.bytesize, :>, 0
  end

  test "GET /admin/pagos rechaza consulta con solo una fecha" do
    get admin_payments_path, params: { fecha_desde: Date.current }

    assert_response :success
    assert_select ".panel-flash", text: /fecha desde y la fecha hasta/i
    assert_select "input[name=fecha_desde][required]"
    assert_select "input[name=fecha_hasta][required]"
  end

  test "GET /admin/pagos rechaza rango con fecha hasta menor que desde" do
    get admin_payments_path, params: {
      fecha_desde: Date.current,
      fecha_hasta: 3.days.ago.to_date
    }

    assert_response :success
    assert_select ".panel-flash", text: /fecha hasta no puede ser menor/i
    assert_select "input[name=fecha_desde][value=?]", Date.current.to_s
    assert_select "input[name=fecha_hasta][value=?]", 3.days.ago.to_date.to_s
  end

  test "GET /admin/pagos/exportar redirige si faltan fechas" do
    get export_admin_payments_path, params: { fecha_desde: Date.current }

    assert_redirected_to admin_payments_path(fecha_desde: Date.current, fecha_hasta: nil)
    assert_equal "Debes indicar la fecha desde y la fecha hasta.", flash[:alert]
  end

  test "GET /admin/pagos/exportar redirige si el rango de fechas es inválido" do
    get export_admin_payments_path, params: {
      fecha_desde: Date.current,
      fecha_hasta: 2.days.ago.to_date
    }

    assert_redirected_to admin_payments_path(
      fecha_desde: Date.current,
      fecha_hasta: 2.days.ago.to_date
    )
    assert_equal "La fecha hasta no puede ser menor que la fecha desde.", flash[:alert]
  end
end
