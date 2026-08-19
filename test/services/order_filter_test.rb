# frozen_string_literal: true

require "test_helper"
require "support/order_factory"

class OrderFilterTest < ActiveSupport::TestCase
  include OrderFactory

  test "sin parámetros no filtra nada y ordena por fecha descendente" do
    vieja = crear_orden
    vieja.update_columns(created_at: 3.days.ago)
    nueva = crear_orden

    filtro = OrderFilter.new({})

    assert filtro.valido?
    assert_not filtro.aplicado?
    assert_equal [ nueva.reference, vieja.reference ], filtro.scope.pluck(:reference)
  end

  test "combina estado, curso y rango de fechas" do
    objetivo = crear_orden(snapshot: { course_code: "AYUR" }, status: "paid")
    crear_orden(snapshot: { course_code: "AYUR" })                       # otro estado
    crear_orden(snapshot: { course_code: "EJO1" }, status: "paid")       # otro curso

    filtro = OrderFilter.new(estado: "paid", curso: "AYUR", desde: Date.current.to_s, hasta: Date.current.to_s)

    assert filtro.valido?
    assert filtro.aplicado?
    assert_equal [ objetivo.reference ], filtro.scope.pluck(:reference)
  end

  test "un rango invertido es inválido y no filtra silenciosamente mal" do
    crear_orden

    filtro = OrderFilter.new(desde: Date.current.to_s, hasta: (Date.current - 1).to_s)

    assert_not filtro.valido?
    assert_includes filtro.errores, "La fecha inicial debe ser anterior a la final."
    assert_equal Order.count, filtro.scope.count
  end

  test "una fecha con formato inválido se reporta como error" do
    filtro = OrderFilter.new(desde: "ayer")

    assert_not filtro.valido?
    assert_match(/fecha inicial no tiene un formato válido/, filtro.errores.first)
  end

  test "un estado inexistente se reporta en vez de devolver una lista vacía sin explicación" do
    filtro = OrderFilter.new(estado: "cancelada")

    assert_not filtro.valido?
    assert_includes filtro.errores, "El estado seleccionado no es válido."
  end

  test "el filtro de estado CRM distingue reportado, pendiente y error" do
    reportada = crear_orden(status: "paid", crm_reported: true)
    pendiente = crear_orden(status: "paid")
    con_error = crear_orden(status: "paid", crm_error: "Timeout")

    assert_equal [ reportada.reference ], OrderFilter.new(crm: "reportado").scope.pluck(:reference)
    assert_equal [ pendiente.reference ], OrderFilter.new(crm: "pendiente").scope.pluck(:reference)
    assert_equal [ con_error.reference ], OrderFilter.new(crm: "error").scope.pluck(:reference)
  end

  test "el resumen ignora el filtro de estado pero respeta el resto del recorte" do
    crear_orden(snapshot: { course_code: "AYUR" }, status: "paid")
    crear_orden(snapshot: { course_code: "AYUR" })
    crear_orden(snapshot: { course_code: "EJO1" }, status: "paid")

    filtro = OrderFilter.new(estado: "paid", curso: "AYUR")
    resumen = filtro.scope_para_resumen.group(:status).count

    assert_equal 1, resumen["paid"]
    assert_equal 1, resumen["pending"]
  end

  test "el nombre del archivo refleja los filtros aplicados" do
    filtro = OrderFilter.new(estado: "paid", curso: "AYUR", crm: "error")

    assert_match(/\Aordenes-paid-ayur-crm-error-\d{8}-\d{4}\.csv\z/, filtro.nombre_archivo)
    assert_match(/\Aordenes-\d{8}-\d{4}\.csv\z/, OrderFilter.new({}).nombre_archivo)
  end
end
