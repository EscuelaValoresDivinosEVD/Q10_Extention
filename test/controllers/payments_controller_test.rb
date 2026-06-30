# frozen_string_literal: true

require "test_helper"

class PaymentsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @token = ENV["PAGOMEDIOS_API_TOKEN"]
    ENV["PAGOMEDIOS_API_TOKEN"] = "test-token" if @token.blank?

    @original_webhook_secret = ENV["PAGOMEDIOS_WEBHOOK_SECRET"]
    ENV["PAGOMEDIOS_WEBHOOK_SECRET"] = "test-webhook-secret"

    @original_q10_report = Q10::PaymentReporter.instance_method(:report!)
    Q10::PaymentReporter.define_method(:report!) do |payment|
      PaymentRecorder.apply_q10_report!(reference: payment.reference, result: { reported: true })
      { reported: true }
    end
  end

  def teardown
    ENV["PAGOMEDIOS_API_TOKEN"] = @token
    ENV["PAGOMEDIOS_WEBHOOK_SECRET"] = @original_webhook_secret
    Q10::PaymentReporter.define_method(:report!, @original_q10_report)
  end

  test "GET /pagar muestra el formulario" do
    get pagar_path
    assert_response :success
    assert_select "form[action=?]", pagar_path
    assert_select "input[name=amount]"
    assert_select "select[name=currency]"
    assert_select "button[type=submit]", text: /Generar enlace de pago/
  end

  test "GET / (root) muestra la landing CLEV, no el formulario de pago" do
    get root_path
    assert_response :success
    assert_select "form[action=?]", acceder_path
    assert_select "h1", text: /Gesti?n del estudiante CLEV/
  end

  test "POST /pagar con monto inv?lido vuelve al formulario con error" do
    post pagar_path, params: { amount: "" }
    assert_response :unprocessable_entity
    assert_select "form[action=?]", pagar_path
    assert_select ".flash.alert", text: /monto v?lido/
  end

  test "POST /pagar con monto cero vuelve al formulario con error" do
    post pagar_path, params: { amount: "0" }
    assert_response :unprocessable_entity
    assert_select ".flash.alert", text: /monto v?lido/
  end

  test "POST /pagar con monto v?lido y API exitosa redirige a Pagomedios y registra pago pendiente en BD" do
    stub_pagomedios_success! do
      post pagar_path, params: { amount: "50", currency: "USD" }
    end
    assert_redirected_to "https://pay.example.com/123"
    payment = Payment.order(:created_at).last
    assert_equal "pending", payment.status
    assert_equal 50.0, payment.amount.to_f
    assert_equal "https://pay.example.com/123", payment.payment_url
    assert_equal "abc-123", payment.pagomedios_token
    assert payment.reference.start_with?("CLEV-")
  end

  test "POST /pagar desde cuotas redirige a Pagomedios y guarda sesi?n" do
    stub_pagomedios_success! do
      post pagar_path, params: {
        amount: "116",
        currency: "USD",
        return_token: "token-test",
        numero_identificacion: "81181178",
        codigo_estudiante: "117845823986",
        consecutivo_credito: "655",
        pending_cuotas_order: "2,3",
        cuotas: "2",
        description: "Pago cuota 2"
      }
    end
    assert_response :redirect
    assert_match %r{\Ahttps://pay\.example\.com/}, response.redirect_url
  end

  test "POST /pagar rechaza cuotas bloqueadas por reporte Q10 pendiente" do
    Payment.create!(
      reference: "CLEV-BLOCKED-CUOTA",
      status: "authorized",
      amount: 30.0,
      currency: "USD",
      numero_identificacion: "81181178",
      consecutivo_credito: 655,
      cuotas: [ "2" ],
      q10_reported: false
    )

    post pagar_path, params: {
      amount: "30",
      currency: "USD",
      return_token: "token-test",
      numero_identificacion: "81181178",
      consecutivo_credito: "655",
      pending_cuotas_order: "2,3",
      cuotas: "2",
      description: "Pago cuota 2"
    }

    assert_response :redirect
    assert_match(/pendiente.*registro.*Q10/i, response.redirect_url)
  end

  test "POST /pagar rechaza cuotas fuera de orden consecutivo" do
    post pagar_path, params: {
      amount: "116",
      currency: "USD",
      return_token: "token-test",
      pending_cuotas_order: "2,3",
      cuotas: "3",
      description: "Pago cuota 3"
    }
    assert_response :redirect
    assert_match(/payment_error=.*cuota/, response.redirect_url)
  end

  test "POST /pagar cuando la API falla muestra error en el formulario" do
    stub_pagomedios_failure! do
      post pagar_path, params: { amount: "25" }
    end
    assert_response :unprocessable_entity
    assert_select "form[action=?]", pagar_path
    assert_select ".flash.alert", text: /enlace de pago|error/i

    payment = Payment.order(:created_at).last
    assert_equal "failed", payment.status
    assert_not_nil payment.error_message
  end

  # --- Webhook de confirmaci?n de pago (Pagomedios POST) ---

  test "POST /payments/webhook desde servidor responde 200 y actualiza pago en BD" do
    seed_credit_payment("PAGO-1772899564")

    post pagomedios_webhook_path,
         params: webhook_params_autorizada,
         headers: { "User-Agent" => "Pagomedios-Webhook/1.0" }
    assert_response :ok

    payment = Payment.find_by!(reference: "PAGO-1772899564")
    assert_equal "authorized", payment.status
    assert payment.q10_reported
    assert_equal "243424", payment.authorization_code
  end

  test "POST /payments/webhook rechaza notificaci?n con secreto inv?lido" do
    seed_credit_payment("CLEV-SECURE")

    post payments_webhook_path(webhook_secret: "wrong-secret"),
         params: webhook_params_autorizada.merge(customValue: "CLEV-SECURE"),
         headers: { "User-Agent" => "Pagomedios-Webhook/1.0" }

    assert_response :forbidden
    payment = Payment.find_by!(reference: "CLEV-SECURE")
    assert_equal "pending", payment.status
  end

  test "POST /payments/webhook desde navegador procesa notificaci?n y muestra confirmaci?n" do
    seed_credit_payment("CLEV-BROWSER", return_token: "token-panel")

    post pagomedios_webhook_path,
         params: webhook_params_autorizada.merge(customValue: "CLEV-BROWSER", amount: "116.00"),
         headers: { "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0" }

    assert_response :success
    assert_select "h1", text: /Pago ejecutado correctamente/
    payment = Payment.find_by!(reference: "CLEV-BROWSER")
    assert_equal "authorized", payment.status
    assert_equal "243424", payment.authorization_code
    assert payment.q10_reported
  end

  test "POST /payments/webhook desde navegador con secreto inv?lido no muta la BD" do
    seed_credit_payment("CLEV-BROWSER-BAD", return_token: "token-panel")

    post payments_webhook_path(webhook_secret: "wrong-secret"),
         params: webhook_params_autorizada.merge(customValue: "CLEV-BROWSER-BAD", amount: "116.00"),
         headers: { "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0" }

    assert_response :success
    assert_select "h1", text: /Pago en proceso/
    payment = Payment.find_by!(reference: "CLEV-BROWSER-BAD")
    assert_equal "pending", payment.status
  end

  test "GET /payments/webhook desde servidor no actualiza pago en BD" do
    seed_credit_payment("CLEV-TEST", return_token: "token-panel")

    get pagomedios_webhook_path,
        params: {
          status: "1",
          customValue: "CLEV-TEST",
          message: "Transaccion aprobada"
        },
        headers: { "User-Agent" => "Pagomedios-Webhook/1.0" }

    assert_response :success
    payment = Payment.find_by!(reference: "CLEV-TEST")
    assert_equal "pending", payment.status
  end

  test "GET /payments/return no actualiza pago en BD con par?metros falsos" do
    seed_credit_payment("CLEV-RETURN", return_token: "token-panel")

    get payment_return_path, params: {
      status: "1",
      customValue: "CLEV-RETURN",
      message: "Transaccion aprobada"
    }

    assert_response :success
    assert_select "h1", text: /Pago en proceso/
    payment = Payment.find_by!(reference: "CLEV-RETURN")
    assert_equal "pending", payment.status
  end

  test "GET /payments/return muestra confirmaci?n tras pago ya autorizado en BD" do
    seed_credit_payment("CLEV-RETURN", return_token: "token-panel")
    PaymentRecorder.update_status!(
      reference: "CLEV-RETURN",
      status: "authorized",
      webhook_payload: { status: "1", message: "Transaccion aprobada" }
    )

    get payment_return_path, params: {
      status: "1",
      customValue: "CLEV-RETURN",
      message: "Transaccion aprobada"
    }

    assert_response :success
    assert_select "h1", text: /Pago ejecutado correctamente/
    assert_match "payment_ref=CLEV-RETURN", response.body
    assert_match "Redirigiendo a tu panel", response.body
  end

  test "POST /payments/webhook con pago rechazado responde 200" do
    seed_credit_payment("PAGO-999")

    post pagomedios_webhook_path, params: {
      status: "2",
      reference: "LP-REJECT123",
      customValue: "PAGO-999",
      message: "Transaccion rechazada",
      amount: "116.00"
    }, headers: { "User-Agent" => "Pagomedios-Webhook/1.0" }

    assert_response :ok
    assert_equal "rejected", Payment.find_by!(reference: "PAGO-999").status
  end

  test "POST /payments/webhook acepta params t?picos de Pagomedios sin authenticity_token" do
    seed_credit_payment("PAGO-1772899564")

    post pagomedios_webhook_path, params: webhook_params_autorizada
    assert_response :ok
  end

  private

  def credit_session(reference, return_token: nil)
    {
      amount: 116.0,
      currency: "USD",
      return_token: return_token,
      codigo_persona: "117845823986",
      codigo_cajero: "221367230991",
      consecutivo_credito: 655,
      cuotas: [ "3" ]
    }
  end

  def seed_credit_payment(reference, return_token: nil)
    PaymentRecorder.record_pending!(
      reference: reference,
      attrs: credit_session(reference, return_token: return_token)
    )
  end

  def pagomedios_webhook_path
    payments_webhook_path(webhook_secret: ENV.fetch("PAGOMEDIOS_WEBHOOK_SECRET"))
  end

  def webhook_params_autorizada
    {
      status: "1",
      reference: "LP-KYDG1772899607",
      authorizationCode: "243424",
      customValue: "PAGO-1772899564",
      clientId: "PM-DS5ie47664",
      transactionDate: "2026-03-07 11:06:56",
      message: "Transaccion aprobada",
      cardNumber: "420000******0000",
      cardBrand: "visa",
      cardHolder: "Cesar Valderrama",
      ipAddress: "200.24.158.125",
      expiryMonth: "03",
      expiryYear: "2029",
      batch: "260307",
      amount: "116.00"
    }
  end

  def stub_pagomedios_success!
    response_body = { "success" => true, "status" => 201, "data" => { "url" => "https://pay.example.com/123", "token" => "abc-123" } }.to_json
    stub_net_http_with_body(response_body, success: true) { yield }
  end

  def stub_pagomedios_failure!
    stub_net_http_with_body({ "error" => "Invalid request" }.to_json, success: false) { yield }
  end

  def stub_net_http_with_body(body, success:, &block)
    fake_response = build_fake_http_response(body: body, success: success)
    fake_http = build_fake_http(request_returns: fake_response)
    stub_class_method(Net::HTTP, :new, fake_http, &block)
  end

  def build_fake_http(request_returns:)
    Object.new.tap do |http|
      http.define_singleton_method(:use_ssl=) { |_| true }
      http.define_singleton_method(:open_timeout=) { |_| nil }
      http.define_singleton_method(:read_timeout=) { |_| nil }
      http.define_singleton_method(:request) { |_| request_returns }
    end
  end

  def build_fake_http_response(body:, success:)
    Object.new.tap do |r|
      r.define_singleton_method(:code) { success ? "201" : "400" }
      r.define_singleton_method(:body) { body }
      r.define_singleton_method(:is_a?) { |klass| success && klass == Net::HTTPSuccess }
    end
  end
end
