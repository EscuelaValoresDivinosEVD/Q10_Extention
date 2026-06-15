# frozen_string_literal: true

require "test_helper"

class Q10::ApiClientFetchEstudianteTest < ActiveSupport::TestCase
  test "fetch_estudiante hace GET a /estudiantes/{id}" do
    captured = {}
    fake_response = Object.new.tap do |response|
      response.define_singleton_method(:code) { "200" }
      response.define_singleton_method(:body) do
        {
          "Numero_identificacion" => "1102369319",
          "Email" => "Yaqueline.lizarazo@evdsky.com"
        }.to_json
      end
      response.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess }
    end

    client = Q10::ApiClient.new(config: Rails.application.config_for(:q10).deep_symbolize_keys.merge(enabled: true))
    client.define_singleton_method(:perform_get) do |uri, _headers|
      captured[:uri] = uri
      fake_response
    end

    result = client.fetch_estudiante(numero_identificacion: "1102369319")

    assert_equal "https://api.q10.com/v1/estudiantes/1102369319", captured[:uri].to_s
    assert_equal "1102369319", result[:data]["Numero_identificacion"]
  end

  test "fetch_estudiante lanza NotFoundError con 404" do
    fake_response = Object.new.tap do |response|
      response.define_singleton_method(:code) { "404" }
      response.define_singleton_method(:body) { "{}" }
    end

    client = Q10::ApiClient.new(config: Rails.application.config_for(:q10).deep_symbolize_keys.merge(enabled: true))
    client.define_singleton_method(:perform_get) { |_uri, _headers| fake_response }

    assert_raises(Q10::ApiClient::NotFoundError) do
      client.fetch_estudiante(numero_identificacion: "9999999999")
    end
  end
end
