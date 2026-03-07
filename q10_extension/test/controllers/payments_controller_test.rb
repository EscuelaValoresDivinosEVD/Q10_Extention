# frozen_string_literal: true

require "test_helper"

class PaymentsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @token = ENV["PAGOMEDIOS_API_TOKEN"]
    ENV["PAGOMEDIOS_API_TOKEN"] = "test-token" if @token.blank?
  end

  def teardown
    ENV["PAGOMEDIOS_API_TOKEN"] = @token
  end

  test "GET /pagar muestra el formulario" do
    get pagar_path
    assert_response :success
    assert_select "form[action=?]", pagar_path
    assert_select "input[name=amount]"
    assert_select "select[name=currency]"
    assert_select "button[type=submit]", text: /Generar enlace de pago/
  end

  test "GET / (root) muestra el formulario de pago" do
    get root_path
    assert_response :success
    assert_select "form[action=?]", pagar_path
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

  test "POST /pagar con monto válido y API exitosa muestra checkout con enlace" do
    stub_pagomedios_success! do
      post pagar_path, params: { amount: "50", currency: "USD" }
    end
    assert_response :success
    assert_select "a.btn-pay[href=?]", "https://pay.example.com/123"
    assert_select ".amount", text: /50/
    assert_select "a", text: /Crear otro pago/
  end

  test "POST /pagar cuando la API falla muestra error en el formulario" do
    stub_pagomedios_failure! do
      post pagar_path, params: { amount: "25" }
    end
    assert_response :unprocessable_entity
    assert_select "form[action=?]", pagar_path
    assert_select ".flash.alert", text: /enlace de pago|error/i
  end

  # --- Webhook de confirmación de pago (Pagomedios POST) ---

  test "POST /payments/webhook con pago autorizado responde 200" do
    post payments_webhook_path, params: webhook_params_autorizada
    assert_response :ok
    assert_equal "", response.body
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
