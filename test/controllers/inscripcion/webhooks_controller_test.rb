# frozen_string_literal: true

require "test_helper"
require "support/order_factory"

module Inscripcion
  class WebhooksControllerTest < ActionDispatch::IntegrationTest
    include OrderFactory
    include ActiveJob::TestHelper

    SECRET = "secreto-inscripcion-de-prueba"

    setup do
      @secret_previo = ENV["INSCRIPCION_WEBHOOK_SECRET"]
      ENV["INSCRIPCION_WEBHOOK_SECRET"] = SECRET
      @order = crear_orden
    end

    teardown do
      ENV["INSCRIPCION_WEBHOOK_SECRET"] = @secret_previo
    end

    def payload_aprobado(order = @order, extras = {})
      {
        status: "1",
        customValue: order.reference,
        reference: "PM-88213",
        authorizationCode: "AUTH-483920",
        cardNumber: "4242424242424242",
        cardBrand: "VISA",
        cardHolder: "V TORRES",
        transactionDate: "2026-07-19 14:33:00",
        message: "Transacción aprobada",
        amount: order.amount.to_s
      }.merge(extras)
    end

    test "un webhook válido marca la orden como pagada y responde 200" do
      post inscripcion_webhook_path(webhook_secret: SECRET), params: payload_aprobado

      assert_response :ok
      assert_equal "paid", @order.reload.status
      assert_equal "**** **** **** 4242", @order.card_number_masked
    end

    test "un webhook con secreto inválido no toca la orden y responde 403" do
      post inscripcion_webhook_path(webhook_secret: "secreto-equivocado"), params: payload_aprobado

      assert_response :forbidden
      assert_equal "pending", @order.reload.status
    end

    test "sin secreto configurado en el servidor se rechaza la notificación" do
      ENV["INSCRIPCION_WEBHOOK_SECRET"] = nil

      post inscripcion_webhook_path(webhook_secret: SECRET), params: payload_aprobado

      assert_response :forbidden
      assert_equal "pending", @order.reload.status
    end

    test "una referencia desconocida se rechaza" do
      post inscripcion_webhook_path(webhook_secret: SECRET),
           params: payload_aprobado.merge(customValue: "INSC-NO-EXISTE")

      assert_response :forbidden
    end

    test "un monto distinto al de la orden se rechaza" do
      post inscripcion_webhook_path(webhook_secret: SECRET), params: payload_aprobado(@order, amount: "1.00")

      assert_response :forbidden
      assert_equal "pending", @order.reload.status
    end

    test "un webhook duplicado es idempotente" do
      2.times { post inscripcion_webhook_path(webhook_secret: SECRET), params: payload_aprobado }

      assert_response :ok
      assert_equal "paid", @order.reload.status
      assert_equal 1, Order.where(reference: @order.reference).count
    end

    test "un webhook rechazado posterior no degrada la orden pagada" do
      post inscripcion_webhook_path(webhook_secret: SECRET), params: payload_aprobado
      post inscripcion_webhook_path(webhook_secret: SECRET),
           params: payload_aprobado.merge(status: "2", authorizationCode: "AUTH-483920")

      assert_equal "paid", @order.reload.status
    end

    test "el pago confirmado encola el reporte al CRM (async)" do
      assert_enqueued_with(job: CrmReportJob, args: [ @order.reference ]) do
        post inscripcion_webhook_path(webhook_secret: SECRET), params: payload_aprobado
      end
    end

    test "un pago rechazado no encola el reporte al CRM" do
      assert_no_enqueued_jobs(only: CrmReportJob) do
        post inscripcion_webhook_path(webhook_secret: SECRET),
             params: payload_aprobado.merge(status: "2")
      end
    end

    test "una orden ya reportada al CRM no vuelve a encolar el job" do
      @order.update_columns(status: "paid", crm_reported: true)

      assert_no_enqueued_jobs(only: CrmReportJob) do
        post inscripcion_webhook_path(webhook_secret: SECRET), params: payload_aprobado
      end
    end

    test "una notificación sin status no altera la orden" do
      post inscripcion_webhook_path(webhook_secret: SECRET),
           params: payload_aprobado.except(:status)

      assert_response :ok
      assert_equal "pending", @order.reload.status
    end

    test "si Pagomedios dispara el POST desde el navegador se redirige a la pantalla de resultado" do
      post inscripcion_webhook_path(webhook_secret: SECRET),
           params: payload_aprobado,
           headers: { "User-Agent" => "Mozilla/5.0 (Macintosh)" }

      assert_redirected_to inscripcion_resultado_path(token: @order.return_token)
      assert_equal "paid", @order.reload.status
    end

    test "el webhook de deudas sigue apuntando a payments y no conoce órdenes de inscripción" do
      # Smoke test de no-regresión: la ruta de deudas existe y es independiente de la nueva.
      assert_equal "/payments/webhook/#{SECRET}", payments_webhook_path(webhook_secret: SECRET)
      assert_equal "/inscripcion/webhook/#{SECRET}", inscripcion_webhook_path(webhook_secret: SECRET)
    end
  end
end
