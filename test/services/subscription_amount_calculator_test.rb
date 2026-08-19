# frozen_string_literal: true

require "test_helper"

class SubscriptionAmountCalculatorTest < ActiveSupport::TestCase
  test "con IVA 0% todo el monto va como base no gravada" do
    desglose = SubscriptionAmountCalculator.desglose_iva(40.0, 0.0)

    assert_equal BigDecimal("40.00"), desglose[:amount_without_tax]
    assert_equal BigDecimal("0"), desglose[:amount_with_tax]
    assert_equal BigDecimal("0"), desglose[:tax_value]
  end

  test "la suma del desglose siempre iguala el monto total" do
    [ [ 40.0, 0.0 ], [ 10.55, 0.0 ], [ 19.99, 0.15 ], [ 33.33, 0.12 ], [ 0.99, 0.15 ] ].each do |monto, tarifa|
      desglose = SubscriptionAmountCalculator.desglose_iva(monto, tarifa)
      suma = desglose[:amount_without_tax] + desglose[:amount_with_tax] + desglose[:tax_value]

      assert_equal BigDecimal(monto.to_s).round(2), suma,
                   "El desglose no cuadra para monto=#{monto} tarifa=#{tarifa}"
    end
  end

  test "con una tarifa distinta de cero separa base gravada e impuesto" do
    desglose = SubscriptionAmountCalculator.desglose_iva(115.0, 0.15)

    assert_equal BigDecimal("0"), desglose[:amount_without_tax]
    assert_equal BigDecimal("100.00"), desglose[:amount_with_tax]
    assert_equal BigDecimal("15.00"), desglose[:tax_value]
  end

  test "acepta montos como string con coma decimal" do
    desglose = SubscriptionAmountCalculator.desglose_iva("25,50", 0.0)

    assert_equal BigDecimal("25.50"), desglose[:amount_without_tax]
  end

  test "la tarifa por defecto es 0% (cursos exentos)" do
    desglose = SubscriptionAmountCalculator.desglose_iva(20.0)

    assert_equal BigDecimal("20.00"), desglose[:amount_without_tax]
    assert_equal BigDecimal("0"), desglose[:tax_value]
  end
end
