# frozen_string_literal: true

require "test_helper"

class Q10::ApiClientReportPaymentTest < ActiveSupport::TestCase
  test "report_pago_credito hace POST a /pagos/creditos" do
    payload = {
      "Codigo_persona" => "117845823986",
      "Codigo_cajero" => "221367230991",
      "Consecutivo_credito" => 655,
      "Fecha_pago" => "2026-03-07",
      "Formas_pago" => [
        {
          "Nombre_cuenta" => "Pagomedios",
          "Nombre_forma_pago" => "Tarjeta Visa",
          "Valor" => 116.0
        }
      ],
      "Observacion" => "Pago CLEV CLEV-TEST"
    }

    captured = {}
    fake_response = Object.new.tap do |r|
      r.define_singleton_method(:code) { "201" }
      r.define_singleton_method(:body) { { "success" => true }.to_json }
      r.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess }
    end

    client = Q10::ApiClient.new(config: Rails.application.config_for(:q10).deep_symbolize_keys.merge(enabled: true))
    client.define_singleton_method(:perform_post) do |uri, _headers, body|
      captured[:uri] = uri
      captured[:body] = JSON.parse(body)
      fake_response
    end

    result = client.report_pago_credito(payload)

    assert_equal "https://api.q10.com/v1/pagos/creditos", captured[:uri].to_s
    assert_equal payload, captured[:body]
    assert result[:success]
  end
end
