# frozen_string_literal: true

require "test_helper"

class Q10::ApiClientFetchOrdenesPagoTest < ActiveSupport::TestCase
  test "fetch_ordenes_pago consulta Codigo_persona y Estado=2" do
    captured = {}
    fake_response = Object.new.tap do |response|
      response.define_singleton_method(:code) { "200" }
      response.define_singleton_method(:body) do
        [
          {
            "Numero_orden_pago" => "1374",
            "Detalles" => [ { "Nombre_producto" => "2026 Prueba de YOGA" } ]
          }
        ].to_json
      end
      response.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess }
    end

    client = Q10::ApiClient.new(
      config: Rails.application.config_for(:q10).deep_symbolize_keys.merge(enabled: true)
    )
    client.define_singleton_method(:perform_get) do |uri, _headers|
      captured[:uri] = uri
      fake_response
    end

    result = client.fetch_ordenes_pago(codigo_persona: "119832177599")

    assert_includes captured[:uri].to_s, "/ordenespago"
    assert_includes captured[:uri].query, "Codigo_persona=119832177599"
    assert_includes captured[:uri].query, "Estado=2"
    assert_equal "1374", result[:data].first["Numero_orden_pago"]
  end
end
