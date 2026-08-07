# frozen_string_literal: true

require "test_helper"

class Q10::ApiClientFetchPeriodosTest < ActiveSupport::TestCase
  test "fetch_periodos consulta Limit y Offset" do
    captured = {}
    fake_response = Object.new.tap do |response|
      response.define_singleton_method(:code) { "200" }
      response.define_singleton_method(:body) do
        [ { "Consecutivo" => 12, "Nombre" => "2026" } ].to_json
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

    result = client.fetch_periodos

    assert_includes captured[:uri].to_s, "/periodos"
    assert_includes captured[:uri].query, "Limit=30"
    assert_includes captured[:uri].query, "Offset=1"
    assert_equal 12, result[:data].first["Consecutivo"]
  end

  test "fetch_creditos acepta consecutivo_periodo explícito" do
    captured = {}
    fake_response = Object.new.tap do |response|
      response.define_singleton_method(:code) { "200" }
      response.define_singleton_method(:body) { [].to_json }
      response.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess }
    end

    client = Q10::ApiClient.new(
      config: Rails.application.config_for(:q10).deep_symbolize_keys.merge(enabled: true, consecutivo_periodo: "12")
    )
    client.define_singleton_method(:perform_get) do |uri, _headers|
      captured[:uri] = uri
      fake_response
    end

    client.fetch_creditos(codigo_persona: "119832177599", consecutivo_periodo: "11")

    assert_includes captured[:uri].query, "Consecutivo_periodo=11"
  end
end
