# frozen_string_literal: true

require "test_helper"
require "support/order_factory"

class OrderRecorderTest < ActiveSupport::TestCase
  include OrderFactory

  WEBHOOK_APROBADO = {
    "status" => "1",
    "reference" => "PM-88213",
    "authorizationCode" => "AUTH-483920",
    "cardNumber" => "4242424242424242",
    "cardBrand" => "VISA",
    "cardHolder" => "V TORRES",
    "transactionDate" => "2026-07-19 14:33:00",
    "message" => "Transacción aprobada"
  }.freeze

  test "apply_webhook! marca la orden como pagada y guarda los datos de la transacción" do
    order = crear_orden

    OrderRecorder.apply_webhook!(reference: order.reference, pagomedios_status: "1", payload: WEBHOOK_APROBADO)
    order.reload

    assert_equal "paid", order.status
    assert_equal "PM-88213", order.pagomedios_reference
    assert_equal "AUTH-483920", order.authorization_code
    assert_equal "VISA", order.card_brand
    assert_equal "V TORRES", order.card_holder
    assert_equal "Transacción aprobada", order.pagomedios_message
    assert_equal Time.zone.parse("2026-07-19 14:33:00"), order.transaction_at
    assert_equal WEBHOOK_APROBADO, order.pagomedios_payload
  end

  test "card_number_masked nunca guarda el PAN completo (ADR-009)" do
    order = crear_orden

    OrderRecorder.apply_webhook!(reference: order.reference, pagomedios_status: "1", payload: WEBHOOK_APROBADO)
    order.reload

    assert_equal "**** **** **** 4242", order.card_number_masked
    assert_not_includes order.card_number_masked, "4242424242424242"
  end

  test "mask_card_number tolera formatos con separadores y valores vacíos" do
    assert_equal "**** **** **** 1111", OrderRecorder.mask_card_number("4111-1111 1111 1111")
    assert_nil OrderRecorder.mask_card_number(nil)
    assert_nil OrderRecorder.mask_card_number("")
    assert_nil OrderRecorder.mask_card_number("sin-digitos")
  end

  test "un webhook rechazado deja la orden en rejected" do
    order = crear_orden

    OrderRecorder.apply_webhook!(reference: order.reference, pagomedios_status: "2", payload: { "message" => "Tarjeta rechazada" })

    assert_equal "rejected", order.reload.status
  end

  test "el estado reversado (3) colapsa en rejected" do
    order = crear_orden

    OrderRecorder.apply_webhook!(reference: order.reference, pagomedios_status: "3", payload: {})

    assert_equal "rejected", order.reload.status
  end

  test "un estado desconocido no degrada ni promueve la orden" do
    order = crear_orden

    OrderRecorder.apply_webhook!(reference: order.reference, pagomedios_status: "99", payload: {})

    assert_equal "pending", order.reload.status
  end

  test "un webhook duplicado no altera una orden ya pagada" do
    order = crear_orden

    OrderRecorder.apply_webhook!(reference: order.reference, pagomedios_status: "1", payload: WEBHOOK_APROBADO)
    primera_actualizacion = order.reload.updated_at

    travel 1.second do
      OrderRecorder.apply_webhook!(reference: order.reference, pagomedios_status: "1", payload: WEBHOOK_APROBADO)
    end

    assert_equal "paid", order.reload.status
    assert_equal 1, Order.where(reference: order.reference).count
    assert_operator order.updated_at, :>=, primera_actualizacion
  end

  test "un webhook rechazado posterior no degrada una orden pagada (regla 5)" do
    order = crear_orden

    OrderRecorder.apply_webhook!(reference: order.reference, pagomedios_status: "1", payload: WEBHOOK_APROBADO)
    OrderRecorder.apply_webhook!(reference: order.reference, pagomedios_status: "2", payload: { "message" => "tardío" })

    order.reload
    assert_equal "paid", order.status
    assert_equal "Transacción aprobada", order.pagomedios_message
  end

  test "apply_webhook! sin orden previa no crea filas y devuelve nil" do
    assert_no_difference -> { Order.count } do
      assert_nil OrderRecorder.apply_webhook!(reference: "INSC-NO-EXISTE", pagomedios_status: "1", payload: {})
    end
  end

  test "record_payment_link! guarda el enlace y limpia el error previo" do
    order = crear_orden(error_message: "intento anterior falló")

    OrderRecorder.record_payment_link!(order, { id: "tok_9f2a", payment_url: "https://payurl.link/abc" })
    order.reload

    assert_equal "tok_9f2a", order.pagomedios_token
    assert_equal "https://payurl.link/abc", order.payment_url
    assert_nil order.error_message
  end

  test "record_failure! deja la orden como intento fallido con el motivo" do
    order = crear_orden

    OrderRecorder.record_failure!(order, "Pagomedios API error 422")
    order.reload

    assert_equal "failed", order.status
    assert_equal "Pagomedios API error 422", order.error_message
    assert_nil order.payment_url
  end

  test "apply_crm_report! marca el reporte exitoso con contacto, tag y respuesta" do
    order = crear_orden(status: "paid")

    OrderRecorder.apply_crm_report!(
      reference: order.reference,
      result: { reported: true, contact_id: "cnt_7Xk2", tag: "ayurveda-2026", response: { "new" => true } }
    )
    order.reload

    assert order.crm_reported?
    assert order.crm_reported_at.present?
    assert_equal "cnt_7Xk2", order.crm_contact_id
    assert_equal "ayurveda-2026", order.crm_tag
    assert_equal({ "new" => true }, order.crm_response)
    assert_nil order.crm_error
    assert_equal :reportado, order.crm_status
  end

  test "apply_crm_report! con fallo conserva el contacto para reintentar solo el tag" do
    order = crear_orden(status: "paid")

    OrderRecorder.apply_crm_report!(
      reference: order.reference,
      result: { reported: false, contact_id: "cnt_7Xk2", error: "Timeout tras 25s" }
    )
    order.reload

    assert_not order.crm_reported?
    assert_equal "cnt_7Xk2", order.crm_contact_id
    assert_equal "Timeout tras 25s", order.crm_error
    assert_equal :error, order.crm_status
  end

  test "fetch_by_return_token ubica la orden del retorno del navegador" do
    order = crear_orden

    assert_equal order, OrderRecorder.fetch_by_return_token(order.return_token)
    assert_nil OrderRecorder.fetch_by_return_token(nil)
    assert_nil OrderRecorder.fetch_by_return_token("token-inexistente")
  end
end
