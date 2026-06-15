# frozen_string_literal: true

require "test_helper"

class PaymentsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @token = ENV["PAGOMEDIOS_API_TOKEN"]
    ENV["PAGOMEDIOS_API_TOKEN"] = "test-token" if @token.blank?

    @original_q10_report = Q10::PaymentReporter.instance_method(:report!)
    Q10::PaymentReporter.define_method(:report!) do |session|
      PaymentSessionStore.mark_q10_reported(session[:reference], response: { success: true })
      { reported: true }
    end
  end

  def teardown
    ENV["PAGOMEDIOS_API_TOKEN"] = @token
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
    assert_select "h1", text: /Gestión del estudiante CLEV/
  end

  test "POST /pagar con monto inválido vuelve al formulario con error" do
    post pagar_path, params: { amount: "" }
    assert_response :unprocessable_entity
    assert_select "form[action=?]", pagar_path
    assert_select ".flash.alert", text: /monto válido/
  end

  test "POST /pagar con monto cero vuelve al formulario con error" do
    post pagar_path, params: { amount: "0" }
    assert_response :unprocessable_entity
    assert_select ".flash.alert", text: /monto válido/
  end

  test "POST /pagar con monto válido y API exitosa redirige a Pagomedios" do
    stub_pagomedios_success! do
      post pagar_path, params: { amount: "50", currency: "USD" }
    end
    assert_redirected_to "https://pay.example.com/123"
    payment = Payment.order(:created_at).last
    assert_equal "pending", payment.status
    assert_equal 50.0, payment.amount.to_f
  end

  test "POST /pagar desde cuotas redirige a Pagomedios y guarda sesión" do
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

  # --- Webhook de confirmación de pago (Pagomedios POST) ---

  test "POST /payments/webhook desde servidor responde 200 y actualiza sesión" do
    PaymentSessionStore.save("PAGO-1772899564", credit_session("PAGO-1772899564"))
    PaymentRecorder.record_pending!(
      reference: "PAGO-1772899564",
      attrs: {
        amount: 116.0,
        currency: "USD",
        consecutivo_credito: 655,
        cuotas: [ "3" ]
      }
    )

    post payments_webhook_path,
         params: webhook_params_autorizada,
         headers: { "User-Agent" => "Pagomedios-Webhook/1.0" }
    assert_response :ok

    session = PaymentSessionStore.fetch("PAGO-1772899564")
    assert_equal "authorized", session[:status]
    assert session[:q10_reported]

    payment = Payment.find_by!(reference: "PAGO-1772899564")
    assert_equal "authorized", payment.status
    assert payment.q10_reported
    assert_equal "243424", payment.authorization_code
  end

  test "POST /payments/webhook desde navegador muestra confirmación y enlace al panel" do
    PaymentSessionStore.save("CLEV-BROWSER", credit_session("CLEV-BROWSER", return_token: "token-panel"))

    post payments_webhook_path,
         params: webhook_params_autorizada.merge(customValue: "CLEV-BROWSER"),
         headers: { "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0" }

    assert_response :success
    assert_select "h1", text: /Pago ejecutado correctamente/
    assert_match %r{/continuar\?}, response.body
    assert_match "payment_success=1", response.body
    session = PaymentSessionStore.fetch("CLEV-BROWSER")
    assert_equal "authorized", session[:status]
  end

  test "GET /payments/webhook desde servidor responde 200" do
    PaymentSessionStore.save("CLEV-TEST", credit_session("CLEV-TEST", return_token: "token-panel"))

    get payments_webhook_path,
        params: {
          status: "1",
          customValue: "CLEV-TEST",
          message: "Transaccion aprobada"
        },
        headers: { "User-Agent" => "Pagomedios-Webhook/1.0" }

    assert_response :ok
    session = PaymentSessionStore.fetch("CLEV-TEST")
    assert_equal "authorized", session[:status]
    assert session[:q10_reported]
  end

  test "GET /payments/return muestra confirmación tras pago aprobado" do
    PaymentSessionStore.save("CLEV-RETURN", credit_session("CLEV-RETURN", return_token: "token-panel"))

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
    post payments_webhook_path, params: {
      status: "2",
      reference: "LP-REJECT123",
      customValue: "PAGO-999",
      message: "Transaccion rechazada"
    }
    assert_response :ok
  end

  test "POST /payments/webhook acepta params típicos de Pagomedios sin authenticity_token" do
    post payments_webhook_path, params: webhook_params_autorizada
    assert_response :ok
  end

  private

  def credit_session(reference, return_token: nil)
    {
      reference: reference,
      status: "pending",
      amount: 116.0,
      return_token: return_token,
      codigo_persona: "117845823986",
      codigo_cajero: "221367230991",
      consecutivo_credito: 655,
      cuotas: [ "3" ]
    }
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
      amount: "60000.00"
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
