# frozen_string_literal: true

require "test_helper"

# Cubre los parámetros ADITIVOS que introduce el funnel de inscripción (factura electrónica,
# desglose de IVA y datos de facturación) y, sobre todo, que SIN ellos el body enviado a
# Pagomedios siga siendo exactamente el del flujo de deudas (no-regresión).
class PagomediosServiceFacturaTest < ActiveSupport::TestCase
  setup do
    @token_previo = ENV["PAGOMEDIOS_API_TOKEN"]
    ENV["PAGOMEDIOS_API_TOKEN"] = "test-token"
  end

  teardown do
    ENV["PAGOMEDIOS_API_TOKEN"] = @token_previo
  end

  test "sin parámetros nuevos el body es el histórico del flujo de deudas" do
    body = capturar_body(amount: 25.50, reference: "CLEV-001", description: "Pago CLEV")

    assert_equal 0, body["generate_invoice"]
    assert_equal 25.50, body["amount"]
    assert_equal 25.50, body["amount_without_tax"]
    assert_equal 0, body["amount_with_tax"]
    assert_equal 0, body["tax_value"]
    assert_not body.key?("document"), "El flujo de deudas no envía datos de facturación"
  end

  test "con factura electrónica envía generate_invoice 1, el desglose y los datos del SRI" do
    body = capturar_body(
      amount: 40.0,
      reference: "INSC-001",
      description: "Inscripción",
      generate_invoice: 1,
      tax_breakdown: { amount_with_tax: 0, amount_without_tax: 40.0, tax_value: 0 },
      customer: { document: "0102030405", name: "Valentina", last_name: "Torres", city: "Quito" }
    )

    assert_equal 1, body["generate_invoice"]
    assert_equal 40.0, body["amount"]
    assert_equal 40.0, body["amount_without_tax"]
    assert_equal "0102030405", body["document"]
    assert_equal "Valentina", body["name"]
    assert_equal "Quito", body["city"]
  end

  test "el desglose enviado siempre cuadra con el monto (invariante de la API)" do
    body = capturar_body(
      amount: 115.0,
      generate_invoice: 1,
      tax_breakdown: { amount_with_tax: 100.0, amount_without_tax: 0, tax_value: 15.0 }
    )

    suma = body["amount_with_tax"] + body["amount_without_tax"] + body["tax_value"]
    assert_equal body["amount"], suma
  end

  private

  def capturar_body(**params)
    capturado = nil
    respuesta = Object.new.tap do |r|
      r.define_singleton_method(:code) { "201" }
      r.define_singleton_method(:body) { { "data" => { "url" => "https://ok.test", "token" => "tok" } }.to_json }
      r.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess }
    end

    fake_http = Object.new.tap do |http|
      http.define_singleton_method(:use_ssl=) { |_| true }
      http.define_singleton_method(:open_timeout=) { |_| nil }
      http.define_singleton_method(:read_timeout=) { |_| nil }
      http.define_singleton_method(:request) do |req|
        capturado = req
        respuesta
      end
    end

    stub_class_method(Net::HTTP, :new, fake_http) do
      ::PagomediosService.new.create_payment(**params)
    end

    JSON.parse(capturado.body)
  end
end
