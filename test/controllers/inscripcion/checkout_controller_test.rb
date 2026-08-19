# frozen_string_literal: true

require "test_helper"
require "support/order_factory"

module Inscripcion
  class CheckoutControllerTest < ActionDispatch::IntegrationTest
    include OrderFactory

    CURSO = {
      code: "EJO1",
      name: "Desarrollo de aplicaciones móviles",
      estado: "Abierto",
      aplica_matricula_en_linea: true,
      cupo_maximo: 10,
      matriculados: 3,
      edition_year: 2026,
      fecha_inicio: Time.zone.parse("2026-01-01T12:00:00Z"),
      fecha_fin: Time.zone.parse("2026-06-30T12:00:00Z")
    }.freeze

    OPCIONES = [
      { option_code: "RESERVA", option_kind: "reserva", option_label: "Reserva de cupo",
        amount: BigDecimal("10.0"), currency: "USD", tax_rate: 0.0 },
      { option_code: "COMPLETO", option_kind: "completo", option_label: "Pago completo",
        amount: BigDecimal("40.0"), currency: "USD", tax_rate: 0.0 }
    ].freeze

    FORMULARIO = {
      codigo: "EJO1",
      opcion_code: "COMPLETO",
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

    # Catálogo de mentira con la misma interfaz que Q10::CourseCatalog.
    class FakeCatalog
      def initialize(curso: CURSO, error: false, deshabilitado: false)
        @curso = curso
        @error = error
        @deshabilitado = deshabilitado
      end

      def find_by_code(codigo) = (@curso if @curso && @curso[:code] == codigo.to_s)
      def error? = @error
      def deshabilitado? = @deshabilitado
      def visible?(curso) = curso.present? && curso[:estado] == "Abierto" && curso[:aplica_matricula_en_linea]
      def cupos?(curso) = curso.present? && curso[:cupo_maximo] > curso[:matriculados]
      def cupos_disponibles(curso) = [ curso[:cupo_maximo] - curso[:matriculados], 0 ].max

      def option_snapshot(course_code:)
        curso = find_by_code(course_code)
        return nil unless curso && visible?(curso) && cupos?(curso)

        { course_code: curso[:code], course_name: curso[:name],
          course_edition_year: curso[:edition_year], tax_rate: 0.0 }
      end
    end

    class FakeGateway
      class << self
        attr_accessor :ultima_llamada, :respuesta
      end

      def create_payment(**params)
        self.class.ultima_llamada = params
        self.class.respuesta || { success: true, payment_url: "https://payurl.link/abc", id: "tok_9f2a" }
      end
    end

    setup do
      FakeGateway.ultima_llamada = nil
      FakeGateway.respuesta = nil
      @secret_previo = ENV["INSCRIPCION_WEBHOOK_SECRET"]
      ENV["INSCRIPCION_WEBHOOK_SECRET"] = "secreto-inscripcion"
    end

    teardown do
      ENV["INSCRIPCION_WEBHOOK_SECRET"] = @secret_previo
    end

    def con_catalogo(catalogo = FakeCatalog.new, &)
      stub_class_method(::Q10::CourseCatalog, :new, catalogo, &)
    end

    def con_precios(opciones = OPCIONES, &)
      stub_class_method(PricingSource, :opciones, opciones, &)
    end

    def con_pasarela(&)
      stub_class_method(::PagomediosService, :new, FakeGateway.new, &)
    end

    # --- show -------------------------------------------------------------------------------

    test "muestra el curso con su disponibilidad real y las opciones de inscripción" do
      con_catalogo do
        con_precios do
          get inscripcion_curso_path(codigo: "EJO1")

          assert_response :success
          assert_select "h1", text: /Desarrollo de aplicaciones móviles/
          assert_select "li", text: /7 cupos disponibles/
          assert_select "input[name=opcion_code][value=COMPLETO]"
          assert_select ".inscripcion-option__amount", text: /\$40\.00/
          assert_select "input[name=email]"
        end
      end
    end

    test "un curso inexistente responde 404 amistoso" do
      con_catalogo(FakeCatalog.new(curso: nil)) do
        get inscripcion_curso_path(codigo: "NO-EXISTE")

        assert_response :not_found
        assert_select "h1", text: /No encontramos el curso/
      end
    end

    test "un curso cerrado o sin matrícula en línea no es accesible" do
      [ CURSO.merge(estado: "Cerrado"), CURSO.merge(aplica_matricula_en_linea: false) ].each do |curso|
        con_catalogo(FakeCatalog.new(curso: curso)) do
          get inscripcion_curso_path(codigo: "EJO1")

          assert_response :not_found
          assert_select "h1", text: /No encontramos el curso/
        end
      end
    end

    test "un curso sin cupos se muestra sin opción de pagar" do
      con_catalogo(FakeCatalog.new(curso: CURSO.merge(matriculados: 10))) do
        con_precios do
          get inscripcion_curso_path(codigo: "EJO1")

          assert_response :success
          assert_select ".flash.alert", text: /ya no tiene cupos disponibles/
          assert_select "button[type=submit]", count: 0
        end
      end
    end

    test "si Q10 no responde y no hay caché se muestra el estado de error, no un 404" do
      con_catalogo(FakeCatalog.new(curso: nil, error: true)) do
        get inscripcion_curso_path(codigo: "EJO1")

        assert_response :service_unavailable
        assert_select "h1", text: /No pudimos confirmar la disponibilidad/
      end
    end

    test "sin opciones de precio configuradas se avisa y no se puede pagar" do
      con_catalogo do
        con_precios([]) do
          get inscripcion_curso_path(codigo: "EJO1")

          assert_response :success
          assert_select ".flash.alert", text: /opciones de inscripción de este curso todavía no están disponibles/
          assert_select "button[type=submit]", count: 0
        end
      end
    end

    test "la opción puede llegar preseleccionada desde el sitio externo" do
      con_catalogo do
        con_precios do
          get inscripcion_curso_path(codigo: "EJO1", opcion: "RESERVA")

          assert_response :success
          assert_select "input[name=opcion_code][value=RESERVA][checked]"
        end
      end
    end

    # --- create -----------------------------------------------------------------------------

    test "crea la orden y redirige a la pasarela" do
      con_catalogo do
        con_precios do
          con_pasarela do
            assert_difference -> { Order.count }, 1 do
              post inscripcion_checkout_path, params: FORMULARIO
            end

            assert_redirected_to "https://payurl.link/abc"
            order = Order.last
            assert_equal "pending", order.status
            assert_equal 40.0, order.amount.to_f
            assert_equal "valentina.torres@correo.com", order.email
          end
        end
      end
    end

    test "el enlace de pago apunta al webhook propio de inscripción" do
      con_catalogo do
        con_precios do
          con_pasarela do
            post inscripcion_checkout_path, params: FORMULARIO

            assert_match(%r{/inscripcion/webhook/secreto-inscripcion}, FakeGateway.ultima_llamada[:notify_url])
            assert_match(%r{/inscripcion/resultado}, FakeGateway.ultima_llamada[:return_url])
          end
        end
      end
    end

    test "un monto manipulado en el request se ignora" do
      con_catalogo do
        con_precios do
          con_pasarela do
            post inscripcion_checkout_path, params: FORMULARIO.merge(amount: "1.00")

            assert_equal 40.0, Order.last.amount.to_f
            assert_equal 40.0, FakeGateway.ultima_llamada[:amount]
          end
        end
      end
    end

    test "datos de facturación incompletos vuelven al formulario con el error" do
      con_catalogo do
        con_precios do
          con_pasarela do
            assert_no_difference -> { Order.count } do
              post inscripcion_checkout_path, params: FORMULARIO.merge(email: "")
            end

            assert_response :unprocessable_entity
            assert_select ".flash.alert", text: /Completa todos los datos/
            # El formulario conserva lo ya escrito.
            assert_select "input[name=first_name][value=Valentina]", count: 1
          end
        end
      end
    end

    test "sin fuente de precio el checkout no crea orden ni llama a la pasarela" do
      con_catalogo do
        con_pasarela do
          assert_no_difference -> { Order.count } do
            post inscripcion_checkout_path, params: FORMULARIO
          end

          assert_response :unprocessable_entity
          assert_nil FakeGateway.ultima_llamada
        end
      end
    end

    test "si Pagomedios falla, la orden queda registrada como intento fallido" do
      con_catalogo do
        con_precios do
          con_pasarela do
            FakeGateway.respuesta = { success: false, error: "Pagomedios API error 422" }

            assert_difference -> { Order.count }, 1 do
              post inscripcion_checkout_path, params: FORMULARIO
            end

            assert_response :unprocessable_entity
            assert_select ".flash.alert", text: /No pudimos iniciar el pago/
            assert_equal "failed", Order.last.status
          end
        end
      end
    end

    # --- result -----------------------------------------------------------------------------

    test "el retorno del navegador muestra el pago completado" do
      order = crear_orden(status: "paid", transaction_at: Time.current, invoice_number: "001-002-000012345")

      get inscripcion_resultado_path(token: order.return_token)

      assert_response :success
      assert_select "h1", text: /Pago completado/
      assert_select "dd", text: order.reference
      assert_select "dd", text: /001-002-000012345/
    end

    test "el retorno antes del webhook muestra 'estamos confirmando tu pago'" do
      order = crear_orden

      get inscripcion_resultado_path(token: order.return_token)

      assert_response :success
      assert_select "h1", text: /Estamos confirmando tu pago/
    end

    test "el retorno de un pago rechazado ofrece reintentar" do
      order = crear_orden(status: "rejected", pagomedios_message: "Tarjeta rechazada")

      get inscripcion_resultado_path(token: order.return_token)

      assert_response :success
      assert_select "h1", text: /rechazado/
      assert_select "a", text: /Intentar de nuevo/
    end

    test "un token desconocido no revienta la pantalla de resultado" do
      get inscripcion_resultado_path(token: "token-inventado")

      assert_response :success
      assert_select "h1", text: /No encontramos tu inscripción/
    end
  end
end
