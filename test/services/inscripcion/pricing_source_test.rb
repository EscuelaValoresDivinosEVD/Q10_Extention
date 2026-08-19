# frozen_string_literal: true

require "test_helper"

module Inscripcion
  class PricingSourceTest < ActiveSupport::TestCase
    CATALOGO_DE_PRUEBA = {
      "EJO1" => [
        { "codigo" => "RESERVA", "tipo" => "reserva", "etiqueta" => "Reserva de cupo", "monto" => 10.0 },
        { "codigo" => "COMPLETO", "tipo" => "completo", "etiqueta" => "Pago completo", "monto" => 40.0 }
      ]
    }.freeze

    test "sin fuente de precio configurada no hay opciones que ofrecer" do
      assert_equal [], PricingSource.opciones(course_code: "EJO1")
      assert_not PricingSource.configurado?(course_code: "EJO1")
    end

    test "sin fuente de precio configurada es imposible armar el snapshot de una orden" do
      error = assert_raises(PricingSource::NotConfiguredError) do
        PricingSource.snapshot(course_code: "EJO1", option_code: "COMPLETO")
      end

      assert_match(/falta definir la fuente del precio/, error.message)
    end

    test "opciones normaliza el contrato configurado" do
      stub_class_method(PricingSource, :catalogo, CATALOGO_DE_PRUEBA) do
        opciones = PricingSource.opciones(course_code: "EJO1")

        assert_equal 2, opciones.size
        reserva = opciones.first
        assert_equal "RESERVA", reserva[:option_code]
        assert_equal "reserva", reserva[:option_kind]
        assert_equal "Reserva de cupo", reserva[:option_label]
        assert_equal BigDecimal("10.0"), reserva[:amount]
        assert_equal "USD", reserva[:currency]
        assert_equal 0.0, reserva[:tax_rate], "El IVA es 0% fijo, no configurable por opción"
      end
    end

    test "snapshot devuelve la opción pedida y nil si el código no existe" do
      stub_class_method(PricingSource, :catalogo, CATALOGO_DE_PRUEBA) do
        snapshot = PricingSource.snapshot(course_code: "EJO1", option_code: "COMPLETO")

        assert_equal "COMPLETO", snapshot[:option_code]
        assert_equal BigDecimal("40.0"), snapshot[:amount]
        assert_nil PricingSource.snapshot(course_code: "EJO1", option_code: "INVENTADA")
      end
    end

    test "descarta opciones sin código o sin monto en vez de cobrar cualquier cosa" do
      catalogo = { "EJO1" => [ { "codigo" => "SIN_MONTO" }, { "monto" => 15.0 }, { "codigo" => "OK", "monto" => 15.0 } ] }

      stub_class_method(PricingSource, :catalogo, catalogo) do
        opciones = PricingSource.opciones(course_code: "EJO1")

        assert_equal [ "OK" ], opciones.map { |opcion| opcion[:option_code] }
      end
    end

    test "un tipo desconocido cae a completo en vez de romper la orden" do
      catalogo = { "EJO1" => [ { "codigo" => "X", "tipo" => "vitalicio", "monto" => 5.0 } ] }

      stub_class_method(PricingSource, :catalogo, catalogo) do
        assert_equal "completo", PricingSource.opciones(course_code: "EJO1").first[:option_kind]
      end
    end

    test "un curso sin opciones configuradas no hereda las de otro" do
      stub_class_method(PricingSource, :catalogo, CATALOGO_DE_PRUEBA) do
        assert_equal [], PricingSource.opciones(course_code: "OTRO")
        assert_equal [], PricingSource.opciones(course_code: nil)
      end
    end
  end
end
