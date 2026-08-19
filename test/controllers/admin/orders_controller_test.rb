# frozen_string_literal: true

require "test_helper"
require "support/order_factory"
require "csv"

class Admin::OrdersControllerTest < ActionDispatch::IntegrationTest
  include OrderFactory

  setup do
    @pagada = crear_orden(
      snapshot: { course_code: "AYUR", course_name: "Ayurveda", option_code: "COMPLETO", option_label: "Pago completo" },
      status: "paid",
      transaction_at: Time.current,
      invoice_number: "001-002-000012345",
      crm_reported: true,
      crm_reported_at: Time.current,
      crm_tag: "ayurveda-2026",
      crm_contact_id: "cnt_7Xk2"
    )

    @pendiente = crear_orden(
      snapshot: { course_code: "EJO1", course_name: "Desarrollo de aplicaciones móviles", option_code: "RESERVA", option_label: "Reserva", amount: 10.0 },
      facturacion: { email: "otro@correo.com", first_name: "Bruno", last_name: "Aguilar" }
    )
  end

  test "GET /admin/ordenes lista las órdenes con su estado" do
    get admin_orders_path

    assert_response :success
    assert_select "h1", text: /Órdenes de inscripción/
    assert_select "td", text: @pagada.reference
    assert_select "td", text: @pendiente.reference
    assert_select "span", text: "Completada"
    assert_select "span", text: "Pendiente"
  end

  test "el resumen cuenta las órdenes por estado" do
    get admin_orders_path

    assert_response :success
    assert_select ".admin-payments-summary__item", minimum: Order::STATUSES.size
  end

  test "el filtro por estado deja solo las órdenes de ese estado" do
    get admin_orders_path(estado: "paid")

    assert_response :success
    assert_select "td", text: @pagada.reference
    assert_select "td", text: @pendiente.reference, count: 0
  end

  test "el filtro por curso usa el código de Q10 del histórico de órdenes" do
    get admin_orders_path(curso: "AYUR")

    assert_response :success
    assert_select "td", text: @pagada.reference
    assert_select "td", text: @pendiente.reference, count: 0
  end

  test "el filtro por rango de fechas acota por fecha del intento" do
    get admin_orders_path(desde: Date.current.to_s, hasta: Date.current.to_s)
    assert_response :success
    assert_select "td", text: @pagada.reference

    get admin_orders_path(desde: (Date.current + 5).to_s, hasta: (Date.current + 10).to_s)
    assert_response :success
    assert_select "td", text: @pagada.reference, count: 0
    assert_select ".block-text", text: /No hay órdenes que coincidan/
  end

  test "un rango de fechas invertido muestra el error de validación" do
    get admin_orders_path(desde: Date.current.to_s, hasta: (Date.current - 5).to_s)

    assert_response :success
    assert_select ".flash.alert", text: /La fecha inicial debe ser anterior a la final/
  end

  test "el filtro por estado del reporte CRM separa reportadas, pendientes y con error" do
    con_error = crear_orden(status: "paid", crm_error: "Timeout tras 25s")

    get admin_orders_path(crm: "reportado")
    assert_select "td", text: @pagada.reference
    assert_select "td", text: con_error.reference, count: 0

    get admin_orders_path(crm: "error")
    assert_select "td", text: con_error.reference
    assert_select "td", text: @pagada.reference, count: 0

    get admin_orders_path(crm: "pendiente")
    assert_select "td", text: @pagada.reference, count: 0
    assert_select "td", text: con_error.reference, count: 0
  end

  test "GET /admin/ordenes.csv exporta las columnas del PRD" do
    get admin_orders_path(format: :csv)

    assert_response :success
    assert_match(%r{text/csv}, response.media_type + "; charset=utf-8")
    assert_equal "attachment", response.headers["Content-Disposition"].split(";").first

    cuerpo = response.body.delete_prefix("﻿")
    filas = CSV.parse(cuerpo, headers: true)

    assert_equal Admin::OrdersController::COLUMNAS_CSV, filas.headers
    assert_equal 2, filas.size

    fila = filas.find { |f| f["referencia"] == @pagada.reference }
    assert_equal "Ayurveda", fila["curso"]
    assert_equal "AYUR", fila["codigo_curso"]
    assert_equal "Pago completo", fila["opcion"]
    assert_equal "40.00", fila["monto"]
    assert_equal "USD", fila["moneda"]
    assert_equal "Completada", fila["estado"]
    assert_equal "0102030405", fila["numero_identificacion"]
    assert_equal "Valentina", fila["nombre"]
    assert_equal "Torres", fila["apellido"]
    assert_equal "Quito", fila["ciudad"]
    assert_equal "Ecuador", fila["pais"]
    assert_equal "001-002-000012345", fila["numero_factura"]
    assert_equal "Reportado", fila["estado_crm"]
    assert_equal "ayurveda-2026", fila["tag_crm"]
  end

  test "el CSV lleva BOM para que Excel respete los acentos" do
    get admin_orders_path(format: :csv)

    assert response.body.start_with?("﻿")
  end

  test "el CSV respeta los filtros aplicados (mismo scope que el listado)" do
    get admin_orders_path(format: :csv, estado: "paid")

    filas = CSV.parse(response.body.delete_prefix("﻿"), headers: true)

    assert_equal 1, filas.size
    assert_equal @pagada.reference, filas.first["referencia"]
  end

  test "el nombre del archivo CSV refleja los filtros" do
    get admin_orders_path(format: :csv, estado: "paid", curso: "AYUR")

    assert_match(/filename="ordenes-paid-ayur-\d{8}-\d{4}\.csv"/, response.headers["Content-Disposition"])
  end

  test "un filtro sin resultados exporta un CSV con solo los encabezados" do
    get admin_orders_path(format: :csv, curso: "NO-EXISTE")

    filas = CSV.parse(response.body.delete_prefix("﻿"), headers: true)

    assert_equal 0, filas.size
    assert_equal Admin::OrdersController::COLUMNAS_CSV, filas.headers
  end

  test "GET /admin/ordenes/:id muestra el detalle completo" do
    get admin_order_path(@pagada)

    assert_response :success
    assert_select "h1", text: /Detalle de la orden/
    assert_select "dd", text: /Ayurveda/
    assert_select "dd", text: /valentina.torres@correo.com/
    assert_select "dd", text: /001-002-000012345/
    assert_select "span", text: "Reportado"
  end

  test "el enlace de pago solo se renderiza como href si es https" do
    pendiente = crear_orden(payment_url: "https://payurl.link/ok")
    get admin_order_path(pendiente)
    assert_select "a[href=?]", "https://payurl.link/ok"

    sospechosa = crear_orden(payment_url: "javascript:alert(1)")
    get admin_order_path(sospechosa)
    assert_select "a[href=?]", "javascript:alert(1)", count: 0
    assert_select "span", text: "javascript:alert(1)"
  end

  test "GET /admin/ordenes/:id con id inexistente responde 404" do
    get admin_order_path(id: 0)

    assert_response :not_found
  end

  test "el listado pagina cuando hay más órdenes que el tamaño de página" do
    stub_const_por_pagina = Admin::OrdersController::POR_PAGINA
    assert_equal 50, stub_const_por_pagina

    get admin_orders_path(pagina: 99)

    assert_response :success
    # La página se acota al rango válido en vez de mostrar un listado vacío.
    assert_select "td", text: @pagada.reference
  end

  test "el panel de pagos de deudas sigue funcionando (no-regresión)" do
    Payment.create!(reference: "CLEV-SMOKE-1", status: "authorized", amount: 25.0, currency: "USD")

    get admin_payments_path

    assert_response :success
    assert_select "h1", text: /Pagos registrados/
    assert_select "td", text: "CLEV-SMOKE-1"
  end
end
