# frozen_string_literal: true

require "test_helper"

class Q10::IdentificationTypesTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
  end

  test "all normaliza tipos activos desde Q10" do
    client = Q10::ApiClient.new(config: Rails.application.config_for(:q10).deep_symbolize_keys.merge(enabled: true))
    client.define_singleton_method(:fetch_tipos_identificacion) do |**|
      {
        data: [
          {
            "Código" => "EC01",
            "Nombre" => "Cédula de identidad",
            "Abreviatura" => "CI",
            "Estado" => true,
            "ExpresiónRegular" => "^\\d{10}$"
          },
          {
            "Codigo" => "EC03",
            "Nombre" => "Pasaporte",
            "Abreviatura" => "PP",
            "Estado" => false,
            "ExpresionRegular" => "^[a-zA-Z0-9_]{4,16}$"
          }
        ]
      }
    end

    types = Q10::IdentificationTypes.new(client: client).all

    assert_equal 1, types.size
    assert_equal "EC01", types.first[:code]
    assert_equal "Cédula de identidad", types.first[:name]
    assert_equal "^\\d{10}$", types.first[:pattern]
  end

  test "valid_document? valida según la expresión regular del tipo" do
    service = Q10::IdentificationTypes.new(client: Q10::ApiClient.new)

    assert service.valid_document?(code: "EC01", document: "1234567890")
    assert_not service.valid_document?(code: "EC01", document: "123")
  end

  test "all usa fallback cuando Q10 está deshabilitado" do
    client = Q10::ApiClient.new(config: Rails.application.config_for(:q10).deep_symbolize_keys.merge(enabled: false))
    types = Q10::IdentificationTypes.new(client: client).all

    assert_includes types.map { |tipo| tipo[:code] }, "EC01"
    assert_includes types.map { |tipo| tipo[:code] }, "EC05"
  end
end
