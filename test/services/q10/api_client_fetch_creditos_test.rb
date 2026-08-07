# frozen_string_literal: true

require "test_helper"

class Q10::ApiClientFetchCreditosTest < ActiveSupport::TestCase
  setup do
    @config = Rails.application.config_for(:q10).deep_symbolize_keys.merge(
      enabled: true,
      consecutivo_periodo: "12"
    )
  end

  test "fetch_creditos usa Codigo_persona cuando está presente" do
    captured = {}
    fake_response = Object.new.tap do |response|
      response.define_singleton_method(:code) { "200" }
      response.define_singleton_method(:body) do
        [
          {
            "Codigo_persona" => "119832177599",
            "Numero_identificacion" => "1102369319",
            "Consecutivo_credito" => 675
          }
        ].to_json
      end
      response.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess }
    end

    client = Q10::ApiClient.new(config: @config)
    client.define_singleton_method(:perform_get) do |uri, _headers|
      captured[:uri] = uri
      fake_response
    end

    result = client.fetch_creditos(
      numero_identificacion: "1102369319",
      codigo_persona: "119832177599"
    )

    assert_includes captured[:uri].query, "Codigo_persona=119832177599"
    assert_includes captured[:uri].query, "Consecutivo_periodo=12"
    refute_includes captured[:uri].query, "Numero_identificacion="
    assert_equal 1, result[:data].size
    assert_equal 675, result[:data].first["Consecutivo_credito"]
  end

  test "fetch_creditos usa Numero_identificacion como fallback" do
    captured = {}
    fake_response = Object.new.tap do |response|
      response.define_singleton_method(:code) { "200" }
      response.define_singleton_method(:body) do
        [
          {
            "Numero_identificacion" => "1102369319",
            "Consecutivo_credito" => 675
          }
        ].to_json
      end
      response.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess }
    end

    client = Q10::ApiClient.new(config: @config)
    client.define_singleton_method(:perform_get) do |uri, _headers|
      captured[:uri] = uri
      fake_response
    end

    result = client.fetch_creditos(numero_identificacion: "1102369319")

    assert_includes captured[:uri].query, "Numero_identificacion=1102369319"
    refute_includes captured[:uri].query, "Codigo_persona="
    assert_equal 1, result[:data].size
  end

  test "fetch_creditos exige Codigo_persona o Numero_identificacion" do
    client = Q10::ApiClient.new(config: @config)

    error = assert_raises(Q10::ApiClient::Error) { client.fetch_creditos }
    assert_match(/Codigo_persona o Numero_identificacion/, error.message)
  end
end
