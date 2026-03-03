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

  private

  def stub_pagomedios_success!
    response_body = { "url_pago" => "https://pay.example.com/123", "id" => "abc-123" }.to_json
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
      r.define_singleton_method(:code) { success ? "200" : "400" }
      r.define_singleton_method(:body) { body }
      r.define_singleton_method(:is_a?) { |klass| success && klass == Net::HTTPSuccess }
    end
  end
end
