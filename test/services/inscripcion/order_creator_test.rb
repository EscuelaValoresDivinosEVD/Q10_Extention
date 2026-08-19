# frozen_string_literal: true

require "test_helper"

module Inscripcion
  class OrderCreatorTest < ActiveSupport::TestCase
    DISPONIBILIDAD = {
      course_code: "EJO1",
      course_name: "Desarrollo de aplicaciones móviles",
      course_edition_year: 2026,
      tax_rate: 0.0
    }.freeze

    OPCIONES = [
      { option_code: "RESERVA", option_kind: "reserva", option_label: "Reserva de cupo",
        amount: BigDecimal("10.0"), currency: "USD", tax_rate: 0.0 },
      { option_code: "COMPLETO", option_kind: "completo", option_label: "Pago completo",
        amount: BigDecimal("40.0"), currency: "USD", tax_rate: 0.0 }
    ].freeze

    FACTURACION = {
      first_name: "Valentina",
      last_name: "Torres",
      identification_type_code: "EC01",
      identification_number: "0102030405",
      email: "valentina.torres@correo.com",
      phone: "+593 99 123 4567",
      address: "Av. Amazonas N34-120",
      city: "Quito",
      country: "Ecuador"
    }.freeze

    # Catálogo de mentira: responde disponibilidad sin salir a Q10.
    class FakeCatalog
      def initialize(snapshot: DISPONIBILIDAD)
        @snapshot = snapshot
      end

      def option_snapshot(course_code:)
        @snapshot
      end
    end

    # Pasarela de mentira: registra el body recibido y permite forzar el fallo.
    class FakeGateway
      class << self
        attr_accessor :ultima_llamada, :respuesta, :excepcion

        def new = allocate
      end

      def create_payment(**params)
        self.class.ultima_llamada = params
        raise ::PagomediosService::Error, self.class.excepcion if self.class.excepcion

        self.class.respuesta || { success: true, payment_url: "https://payurl.link/abc", id: "tok_9f2a" }
      end
    end

    setup do
      FakeGateway.ultima_llamada = nil
      FakeGateway.respuesta = nil
      FakeGateway.excepcion = nil
    end

    def crear(option_code: "COMPLETO", billing: FACTURACION, catalog: FakeCatalog.new)
      OrderCreator.new(
        course_code: "EJO1",
        option_code: option_code,
        billing: billing,
        notify_url: "https://clev.test/inscripcion/webhook/secreto",
        return_url_builder: ->(order) { "https://clev.test/inscripcion/resultado?token=#{order.return_token}" },
        catalog: catalog,
        gateway: FakeGateway
      ).call
    end

    def con_precios(&)
      stub_class_method(PricingSource, :opciones, OPCIONES, &)
    end

    test "crea la orden pending y devuelve el enlace de pago" do
      con_precios do
        resultado = crear

        assert resultado.exito?
        assert_equal "https://payurl.link/abc", resultado.payment_url

        order = resultado.order.reload
        assert_equal "pending", order.status
        assert_equal "EJO1", order.q10_course_code
        assert_equal "COMPLETO", order.option_code
        assert_equal "Pago completo", order.option_label
        assert_equal 40.0, order.amount.to_f
        assert_equal 2026, order.course_edition_year
        assert_equal "tok_9f2a", order.pagomedios_token
        assert_equal "https://payurl.link/abc", order.payment_url
      end
    end

    test "el monto sale del catálogo de precios, nunca del request" do
      con_precios do
        resultado = crear(billing: FACTURACION.merge(amount: "1.00"))

        assert_equal 40.0, resultado.order.amount.to_f
        assert_equal 40.0, FakeGateway.ultima_llamada[:amount]
      end
    end

    test "pide factura electrónica con el desglose de IVA y los datos del SRI" do
      con_precios do
        crear

        llamada = FakeGateway.ultima_llamada
        assert_equal 1, llamada[:generate_invoice]
        assert_equal 40.0, llamada[:tax_breakdown][:amount_without_tax].to_f
        assert_equal 0.0, llamada[:tax_breakdown][:amount_with_tax].to_f
        assert_equal 0.0, llamada[:tax_breakdown][:tax_value].to_f
        assert_equal "0102030405", llamada[:customer][:document]
        assert_equal "Valentina", llamada[:customer][:name]
        assert_equal "Quito", llamada[:customer][:city]
        assert_equal "Ecuador", llamada[:customer][:country]
      end
    end

    test "el enlace apunta al webhook y al retorno propios del funnel de inscripción" do
      con_precios do
        resultado = crear
        llamada = FakeGateway.ultima_llamada

        assert_equal "https://clev.test/inscripcion/webhook/secreto", llamada[:notify_url]
        assert_includes llamada[:return_url], resultado.order.return_token
        assert_includes llamada[:reference], "INSC-"
      end
    end

    test "la orden existe aunque Pagomedios falle (tracking del intento)" do
      con_precios do
        FakeGateway.respuesta = { success: false, error: "Pagomedios API error 422" }

        assert_difference -> { Order.count }, 1 do
          resultado = crear

          assert_not resultado.exito?
          assert_equal :pagomedios, resultado.motivo
          assert_equal "failed", resultado.order.reload.status
          assert_equal "Pagomedios API error 422", resultado.order.error_message
          assert_nil resultado.order.payment_url
        end
      end
    end

    test "una excepción de la pasarela también deja la orden como intento fallido" do
      con_precios do
        FakeGateway.excepcion = "Respuesta inválida de Pagomedios"

        resultado = crear

        assert_not resultado.exito?
        assert_equal "failed", resultado.order.reload.status
        assert_match(/Respuesta inválida/, resultado.order.error_message)
      end
    end

    test "no crea orden si el curso dejó de estar disponible en Q10" do
      con_precios do
        assert_no_difference -> { Order.count } do
          resultado = crear(catalog: FakeCatalog.new(snapshot: nil))

          assert_not resultado.exito?
          assert_equal :no_disponible, resultado.motivo
        end
        assert_nil FakeGateway.ultima_llamada
      end
    end

    test "sin fuente de precio no se crea orden ni se llama a la pasarela" do
      assert_no_difference -> { Order.count } do
        resultado = crear

        assert_not resultado.exito?
        assert_equal :precio_no_configurado, resultado.motivo
        assert_match(/todavía no están disponibles/, resultado.error)
      end
      assert_nil FakeGateway.ultima_llamada
    end

    test "una opción inexistente se rechaza" do
      con_precios do
        assert_no_difference -> { Order.count } do
          resultado = crear(option_code: "INVENTADA")

          assert_not resultado.exito?
          assert_equal :opcion_invalida, resultado.motivo
        end
      end
    end

    test "faltan datos de facturación: no se crea orden" do
      con_precios do
        OrderCreator::CAMPOS_FACTURACION.each do |campo|
          assert_no_difference -> { Order.count } do
            resultado = crear(billing: FACTURACION.merge(campo => ""))

            assert_not resultado.exito?, "#{campo} debería ser obligatorio"
            assert_equal :validacion, resultado.motivo
          end
        end
      end
    end

    test "correo inválido e identificación que no cumple el formato del tipo" do
      con_precios do
        resultado = crear(billing: FACTURACION.merge(email: "no-es-correo"))
        assert_not resultado.exito?
        assert_match(/correo válido/, resultado.error)

        resultado = crear(billing: FACTURACION.merge(identification_number: "123"))
        assert_not resultado.exito?
        assert_match(/número de identificación/, resultado.error)
      end
    end
  end
end
