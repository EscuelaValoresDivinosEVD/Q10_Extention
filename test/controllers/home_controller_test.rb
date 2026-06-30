# frozen_string_literal: true

require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  setup { Rails.cache.clear }

  test "GET / muestra la landing CLEV" do
    get root_path
    assert_response :success
    assert_select "h1", text: /Gestión del estudiante CLEV/
    assert_select "form[action=?]", acceder_path
    assert_select "select[name=document_type]"
    assert_select "select[name=document_type] option[value=?]", "EC01", text: /Cédula de identidad/
    assert_select "input[name=document]"
    assert_select "input[name=email]"
  end

  test "GET /acceder redirige al inicio" do
    get "/acceder"
    assert_redirected_to root_path
  end

  test "POST /acceder con datos válidos redirige al inicio y muestra modal" do
    post acceder_path, params: {
      document_type: "EC01",
      document: "1234567890",
      email: "alumno@correo.com"
    }
    assert_redirected_to root_path
    follow_redirect!
    assert_select "dialog.clev-modal#clev-email-modal"
    assert_match(/alumno@correo\.com/, response.body)
    assert_match(/correo electrónico/i, response.body)
  end

  test "POST /acceder con datos inválidos redirige al formulario con error" do
    post acceder_path, params: { document_type: "", document: "", email: "" }
    assert_response :redirect
    assert_match %r{\Ahttp://www\.example\.com/?}, response.redirect_url
    follow_redirect!
    assert_select "form[action=?]", acceder_path
    assert_select ".clev-flash--alert"
  end

  test "POST /acceder bloquea tras más de 15 solicitudes desde la misma IP" do
    15.times do
      post acceder_path, params: { document_type: "", document: "", email: "" }
      assert_response :redirect
    end

    post acceder_path, params: { document_type: "", document: "", email: "" }
    assert_redirected_to root_path
    follow_redirect!
    assert_select ".clev-flash--alert", text: /bloqueado temporalmente/
  end

  test "POST /acceder rechaza tipo de documento distinto al registrado en Q10" do
    with_q10_student(
      "Codigo_tipo_identificacion" => "EC03",
      "Numero_identificacion" => "1102369319",
      "Email" => "Yaqueline.lizarazo@evdsky.com"
    ) do
      post acceder_path, params: {
        document_type: "EC01",
        document: "1102369319",
        email: "yaqueline.lizarazo@evdsky.com"
      }

      assert_response :redirect
      follow_redirect!
      assert_select ".clev-flash--alert", text: /tipo de documento seleccionado no coincide/
    end
  end

  private

  def with_q10_student(estudiante)
    client = Object.new
    client.define_singleton_method(:enabled?) { true }
    client.define_singleton_method(:fetch_estudiante) { |**| { data: estudiante } }
    client.define_singleton_method(:fetch_creditos) { |**| { data: [ estudiante.merge("Consecutivo_credito" => 1) ] } }
    client.define_singleton_method(:fetch_tipos_identificacion) do |**|
      {
        data: [
          { "Código" => "EC01", "Nombre" => "Cédula de identidad", "Estado" => true, "ExpresiónRegular" => "^\\d{10}$" },
          { "Código" => "EC03", "Nombre" => "Pasaporte", "Estado" => true, "ExpresionRegular" => "^[a-zA-Z0-9_]{4,16}$" }
        ]
      }
    end

    original_new = Q10::ApiClient.method(:new)
    Q10::ApiClient.define_singleton_method(:new) { |**| client }
    yield
  ensure
    Q10::ApiClient.define_singleton_method(:new, original_new)
  end
end
