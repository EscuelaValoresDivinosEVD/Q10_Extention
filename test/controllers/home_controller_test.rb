# frozen_string_literal: true

require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "GET / muestra la landing CLEV" do
    get root_path
    assert_response :success
    assert_select "h1", text: /Gestión del estudiante CLEV/
    assert_select "form[action=?]", acceder_path
    assert_select "select[name=document_type]"
    assert_select "input[name=document]"
    assert_select "input[name=email]"
  end

  test "POST /acceder con datos válidos muestra modal de correo sin redirigir a pagar" do
    post acceder_path, params: {
      document_type: "cc",
      document: "10203040",
      email: "alumno@correo.com"
    }
    assert_response :success
    assert_not_predicate response, :redirect?
    assert_select "dialog.clev-modal#clev-email-modal"
    assert_match(/alumno@correo\.com/, response.body)
    assert_match(/correo electrónico/i, response.body)
  end

  test "POST /acceder con datos inválidos vuelve al formulario" do
    post acceder_path, params: { document_type: "", document: "", email: "" }
    assert_response :unprocessable_entity
    assert_select "form[action=?]", acceder_path
    assert_select ".clev-flash--alert"
  end
end
