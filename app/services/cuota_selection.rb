# frozen_string_literal: true

class CuotaSelection
  class << self
    def numero(cuota)
      (cuota["Numero_cuota"] || cuota["Número_cuota"]).to_s
    end

    def pendiente?(cuota)
      cuota["Pendiente"].to_f.positive?
    end

    def sorted(cuotas)
      Array(cuotas).sort_by { |cuota| [ fecha_orden(cuota), numero(cuota).to_i ] }
    end

    def pending_numbers_in_order(cuotas)
      sorted(cuotas).select { |cuota| pendiente?(cuota) }.map { |cuota| numero(cuota) }
    end

    def valid_selection?(pending_order, selected)
      order = Array(pending_order).map(&:to_s).reject(&:blank?)
      chosen = Array(selected).map(&:to_s).reject(&:blank?)
      return false if chosen.empty?

      expected = order.first(chosen.length)
      chosen == expected
    end

    private

    def fecha_orden(cuota)
      raw = cuota["Fecha_cuota"].to_s
      return [ 9999, 12, 31 ] if raw.blank?

      date = Date.parse(raw.first(10))
      [ date.year, date.month, date.day ]
    rescue ArgumentError
      [ 9999, 12, 31 ]
    end
  end
end
