# frozen_string_literal: true

require "test_helper"

class CuotaSelectionTest < ActiveSupport::TestCase
  test "ordena cuotas pendientes por fecha más antigua primero" do
    cuotas = [
      { "Numero_cuota" => 3, "Fecha_cuota" => "2026-04-01", "Pendiente" => 50 },
      { "Numero_cuota" => 2, "Fecha_cuota" => "2026-03-01", "Pendiente" => 40 },
      { "Numero_cuota" => 1, "Fecha_cuota" => "2026-02-01", "Pendiente" => 0 }
    ]

    assert_equal %w[2 3], CuotaSelection.pending_numbers_in_order(cuotas)
  end

  test "valid_selection? exige prefijo consecutivo desde la más vencida" do
    order = %w[2 3 4]

    assert CuotaSelection.valid_selection?(order, %w[2])
    assert CuotaSelection.valid_selection?(order, %w[2 3])
    assert CuotaSelection.valid_selection?(order, %w[2 3 4])
    assert_not CuotaSelection.valid_selection?(order, %w[3])
    assert_not CuotaSelection.valid_selection?(order, %w[2 4])
    assert_not CuotaSelection.valid_selection?(order, [])
  end
end
