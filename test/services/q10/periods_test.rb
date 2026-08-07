# frozen_string_literal: true

require "test_helper"

class Q10::PeriodsTest < ActiveSupport::TestCase
  setup { Rails.cache.clear }

  test "elige por defecto el periodo del año en curso" do
    client = Object.new
    client.define_singleton_method(:enabled?) { true }
    client.define_singleton_method(:fetch_periodos) do |**|
      {
        data: [
          { "Consecutivo" => 11, "Nombre" => "2025", "Estado" => true, "Ordenamiento" => 9 },
          { "Consecutivo" => 12, "Nombre" => "2026", "Estado" => true, "Ordenamiento" => 10 },
          { "Consecutivo" => 99, "Nombre" => "2099", "Estado" => false, "Ordenamiento" => 99 }
        ]
      }
    end

    periods = Q10::Periods.new(client: client, year: 2026)

    assert_equal "12", periods.default_consecutivo
    assert_equal [ [ "2026", "12" ], [ "2025", "11" ] ], periods.options_for_select
  end

  test "el combo solo muestra año vigente y anterior" do
    client = Object.new
    client.define_singleton_method(:enabled?) { true }
    client.define_singleton_method(:fetch_periodos) do |**|
      {
        data: [
          { "Consecutivo" => 10, "Nombre" => "2024", "Estado" => true, "Ordenamiento" => 8 },
          { "Consecutivo" => 11, "Nombre" => "2025", "Estado" => true, "Ordenamiento" => 9 },
          { "Consecutivo" => 12, "Nombre" => "2026", "Estado" => true, "Ordenamiento" => 10 },
          { "Consecutivo" => 3, "Nombre" => "2023", "Estado" => true, "Ordenamiento" => 1 }
        ]
      }
    end

    periods = Q10::Periods.new(client: client, year: 2026)

    assert_equal [ [ "2026", "12" ], [ "2025", "11" ] ], periods.options_for_select
  end

  test "resolve usa el solicitado si existe en el combo reciente" do
    client = Object.new
    client.define_singleton_method(:enabled?) { true }
    client.define_singleton_method(:fetch_periodos) do |**|
      {
        data: [
          { "Consecutivo" => 10, "Nombre" => "2024", "Estado" => "verdadero" },
          { "Consecutivo" => 11, "Nombre" => "2025", "Estado" => "verdadero" },
          { "Consecutivo" => 12, "Nombre" => "2026", "Estado" => "verdadero" }
        ]
      }
    end

    periods = Q10::Periods.new(client: client, year: 2026)

    assert_equal "11", periods.resolve("11")
    assert_equal "12", periods.resolve("10")
    assert_equal "12", periods.resolve("999")
  end
end