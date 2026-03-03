# frozen_string_literal: true

require "test_helper"

class PagomediosServiceTest < ActiveSupport::TestCase
  def setup
    @original_token = ENV["PAGOMEDIOS_API_TOKEN"]
    ENV["PAGOMEDIOS_API_TOKEN"] = "test-token"
  end

  def teardown
    ENV["PAGOMEDIOS_API_TOKEN"] = @original_token
  end

  test "raise Error cuando PAGOMEDIOS_API_TOKEN no está configurado" do
    ENV["PAGOMEDIOS_API_TOKEN"] = nil
    assert_raises(::PagomediosService::Error) do
      ::PagomediosService.new
    end
  end

  test "create_payment con respuesta exitosa devuelve success y payment_url" do
    result = nil
    stub_http_success! do
      result = ::PagomediosService.new.create_payment(amount: 100)
    end
    assert result[:success]
    assert_equal "https://pay.example.com/xyz", result[:payment_url]
    assert_equal "xyz", result[:id]
    assert_equal 100, result[:amount]
  end

  test "create_payment con respuesta 4xx devuelve success false y error" do
    result = nil
    stub_http_error!(code: "400", body: "Bad Request") do
      result = ::PagomediosService.new.create_payment(amount: 50)
    end
    assert_not result[:success]
    assert result[:error].present?
  end

  test "create_payment pasa monto, moneda y descripción al API" do
    request_captured = nil
    stub_capture_request do |req|
      request_captured = req
    end
    assert request_captured
    body = JSON.parse(request_captured.body)
    assert_equal 25.50, body["monto"]
    assert_equal "USD", body["moneda"]
    assert_equal "Prueba", body["descripcion"]
    assert_equal "REF-001", body["referencia"]
  end

  private

  def stub_http_success!(&block)
    body = { "url_pago" => "https://pay.example.com/xyz", "id" => "xyz" }.to_json
    stub_net_http(body: body, success: true, &block)
  end

  def stub_http_error!(code: "400", body: "Error", &block)
    stub_net_http(body: body, success: false, code: code, &block)
  end

  def stub_capture_request(&capture_block)
    fake_http = Object.new.tap do |http|
      http.define_singleton_method(:use_ssl=) { |_| true }
      http.define_singleton_method(:open_timeout=) { |_| nil }
      http.define_singleton_method(:read_timeout=) { |_| nil }
      http.define_singleton_method(:request) do |req|
        capture_block&.call(req)
        build_fake_response(body: { "url_pago" => "https://ok.com", "id" => "1" }.to_json, success: true)
      end
    end
    stub_class_method(Net::HTTP, :new, fake_http) do
      ::PagomediosService.new.create_payment(
        amount: 25.50,
        currency: "USD",
        description: "Prueba",
        reference: "REF-001"
      )
    end
  end

  def stub_net_http(body:, success:, code: nil, &block)
    response = build_fake_response(body: body, success: success, code: code || (success ? "200" : "400"))
    fake_http = Object.new.tap do |http|
      http.define_singleton_method(:use_ssl=) { |_| true }
      http.define_singleton_method(:open_timeout=) { |_| nil }
      http.define_singleton_method(:read_timeout=) { |_| nil }
      http.define_singleton_method(:request) { |_| response }
    end
    stub_class_method(Net::HTTP, :new, fake_http, &block)
  end

  def build_fake_response(body:, success:, code: "200")
    Object.new.tap do |r|
      r.define_singleton_method(:code) { code }
      r.define_singleton_method(:body) { body }
      r.define_singleton_method(:is_a?) { |klass| success && klass == Net::HTTPSuccess }
    end
  end
end
