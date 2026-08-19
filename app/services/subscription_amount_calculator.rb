# frozen_string_literal: true

require "bigdecimal"
require "bigdecimal/util"

# Desglose de IVA de una opción de inscripción.
#
# Invariante de Pagomedios API v2: amount == amount_with_tax + amount_without_tax + tax_value,
# todos con 2 decimales. Se calcula con BigDecimal para que la suma cuadre exacta y no falle
# el check constraint `chk_orders_desglose_iva_cuadra`.
#
# Los cursos de CLEV son servicios educativos exentos: la tarifa siempre es 0.0 (ADR-004).
# La fórmula general se conserva por si el tratamiento fiscal cambia en el futuro.
module SubscriptionAmountCalculator
  module_function

  ZERO = BigDecimal("0")

  def desglose_iva(amount, tax_rate = 0.0)
    total = to_decimal(amount).round(2)
    rate  = to_decimal(tax_rate)

    # IVA 0%: todo el monto va como base no gravada.
    return { amount_without_tax: total, amount_with_tax: ZERO, tax_value: ZERO } if rate.zero?

    base = (total / (1 + rate)).round(2)
    # El residuo del redondeo se absorbe en el impuesto para que la suma cuadre exacta.
    iva = (total - base).round(2)

    { amount_without_tax: ZERO, amount_with_tax: base, tax_value: iva }
  end

  def to_decimal(value)
    case value
    when BigDecimal then value
    when Numeric then value.to_s.to_d
    else value.to_s.tr(",", ".").to_d
    end
  rescue ArgumentError
    ZERO
  end
end
