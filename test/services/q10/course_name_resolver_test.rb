# frozen_string_literal: true

require "test_helper"

class Q10::CourseNameResolverTest < ActiveSupport::TestCase
  test "mapea Numero_orden_pago a Nombre_producto" do
    client = Object.new
    client.define_singleton_method(:enabled?) { true }
    client.define_singleton_method(:fetch_ordenes_pago) do |**|
      {
        data: [
          {
            "Numero_orden_pago" => "1374",
            "Detalles" => [ { "Nombre_producto" => "2026 Prueba de YOGA" } ]
          },
          {
            "Numero_orden_pago" => "1345",
            "Detalles" => [ { "Nombre_producto" => "2026Curso Prueba 2" } ]
          }
        ]
      }
    end

    map = Q10::CourseNameResolver.new(client: client).product_names_by_orden(codigo_persona: "119832177599")

    assert_equal "2026 Prueba de YOGA", map["1374"]
    assert_equal "2026Curso Prueba 2", map["1345"]
  end

  test "resuelve el curso del crédito por Numero_orden_pago" do
    resolver = Q10::CourseNameResolver.new(client: Object.new.tap { |c| c.define_singleton_method(:enabled?) { false } })
    credit = {
      "Consecutivo_credito" => 675,
      "Ordenes_pago" => [ { "Numero_orden_pago" => "1374" } ]
    }
    product_by_orden = { "1374" => "2026 Prueba de YOGA" }

    assert_equal "2026 Prueba de YOGA", resolver.course_name_for_credit(credit, product_by_orden)
  end

  test "sin orden coincidente retorna nil" do
    resolver = Q10::CourseNameResolver.new(client: Object.new.tap { |c| c.define_singleton_method(:enabled?) { false } })
    credit = { "Ordenes_pago" => [ { "Numero_orden_pago" => "9999" } ] }

    assert_nil resolver.course_name_for_credit(credit, { "1374" => "YOGA" })
  end
end
