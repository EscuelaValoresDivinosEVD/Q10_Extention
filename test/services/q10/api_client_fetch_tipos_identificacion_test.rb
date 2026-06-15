# frozen_string_literal: true

require "test_helper"

class Q10::ApiClientFetchTiposIdentificacionTest < ActiveSupport::TestCase
  test "fetch_tipos_identificacion hace GET a /tiposidentificacion con Limit y Offset" do
    captured = {}
    fake_response = Object.new.tap do |response|
      response.define_singleton_method(:code) { "200" }
      response.define_singleton_method(:body) do
        [
          {
            "Código" => "EC01",
            "Nombre" => "Cédula de identidad",
            "Abreviatura" => "CI",
            "Estado" => true,
            "ExpresiónRegular" => "^\\d{10}$"
          }
        ].to_json
      end
      response.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess }
    end

    client = Q10::ApiClient.new(config: Rails.application.config_for(:q10).deep_symbolize_keys.merge(enabled: true))
    client.define_singleton_method(:perform_get) do |uri, _headers|
      captured[:uri] = uri
      fake_response
    end

    result = client.fetch_tipos_identificacion(limit: 30, offset: 1)

    assert_equal "https://api.q10.com/v1/tiposidentificacion?Limit=30&Offset=1", captured[:uri].to_s
    assert_equal "EC01", result[:data].first["Código"]
  end
end
