# frozen_string_literal: true

require "test_helper"

class Q10::StudentAccessVerifierTest < ActiveSupport::TestCase
  test "valida correo coincidente con el payload oficial de Q10" do
    client = build_client(
      fetch_estudiante: {
        data: {
          "Codigo_estudiante" => "113947807339",
          "Primer_nombre" => "Carlos",
          "Primer_apellido" => "Bedoya",
          "Numero_identificacion" => "5467567",
          "Codigo_tipo_identificacion" => "EC01",
          "Email" => "BedoyaCorrea@gmail.com",
          "Nombre_programa" => "Desarrollo de software"
        }
      }
    )

    result = Q10::StudentAccessVerifier.new(client: client).verify!(
      numero_identificacion: "5467567",
      email: "bedoyacorrea@gmail.com",
      codigo_tipo_identificacion: "EC01"
    )

    assert result[:valid]
    assert_equal "5467567", result[:estudiante]["Numero_identificacion"]
    assert_equal "BedoyaCorrea@gmail.com", result[:estudiante]["Email"]
  end

  test "valida tipo de identificación coincidente tras validar correo" do
    client = build_client(
      fetch_estudiante: {
        data: {
          "Numero_identificacion" => "1102369319",
          "Codigo_tipo_identificacion" => "EC01",
          "Email" => "Yaqueline.lizarazo@evdsky.com"
        }
      }
    )

    result = Q10::StudentAccessVerifier.new(client: client).verify!(
      numero_identificacion: "1102369319",
      email: "yaqueline.lizarazo@evdsky.com",
      codigo_tipo_identificacion: "EC01"
    )

    assert result[:valid]
  end

  test "rechaza tipo de identificación distinto al registrado en Q10" do
    client = build_client(
      fetch_estudiante: {
        data: {
          "Codigo_estudiante" => "119832177599",
          "Numero_identificacion" => "1102369319",
          "Codigo_tipo_identificacion" => "EC03",
          "Email" => "Yaqueline.lizarazo@evdsky.com"
        }
      }
    )

    result = Q10::StudentAccessVerifier.new(client: client).verify!(
      numero_identificacion: "1102369319",
      email: "yaqueline.lizarazo@evdsky.com",
      codigo_tipo_identificacion: "EC01"
    )

    assert_not result[:valid]
    assert_equal :document_type_mismatch, result[:reason]
  end

  test "rechaza cuando Q10 no tiene código de tipo de identificación" do
    client = build_client(
      fetch_estudiante: {
        data: {
          "Numero_identificacion" => "1102369319",
          "Email" => "Yaqueline.lizarazo@evdsky.com"
        }
      }
    )

    result = Q10::StudentAccessVerifier.new(client: client).verify!(
      numero_identificacion: "1102369319",
      email: "yaqueline.lizarazo@evdsky.com",
      codigo_tipo_identificacion: "EC01"
    )

    assert_not result[:valid]
    assert_equal :missing_document_type, result[:reason]
  end

  test "rechaza correo distinto al registrado" do
    client = build_client(
      fetch_estudiante: {
        data: {
          "Numero_identificacion" => "1102369319",
          "Email" => "Yaqueline.lizarazo@evdsky.com"
        }
      }
    )

    result = Q10::StudentAccessVerifier.new(client: client).verify!(
      numero_identificacion: "1102369319",
      email: "otro@correo.com"
    )

    assert_not result[:valid]
    assert_equal :email_mismatch, result[:reason]
  end

  test "rechaza cuando Numero_identificacion de la respuesta no coincide" do
    client = build_client(
      fetch_estudiante: {
        data: {
          "Numero_identificacion" => "1111111111",
          "Email" => "alumno@correo.com"
        }
      }
    )

    result = Q10::StudentAccessVerifier.new(client: client).verify!(
      numero_identificacion: "5467567",
      email: "alumno@correo.com"
    )

    assert_not result[:valid]
    assert_equal :not_found, result[:reason]
  end

  test "rechaza estudiante no encontrado" do
    client = Object.new
    client.define_singleton_method(:enabled?) { true }
    client.define_singleton_method(:fetch_estudiante) do |**|
      raise Q10::ApiClient::NotFoundError, "Estudiante no encontrado en Q10."
    end

    result = Q10::StudentAccessVerifier.new(client: client).verify!(
      numero_identificacion: "9999999999",
      email: "alumno@correo.com"
    )

    assert_not result[:valid]
    assert_equal :not_found, result[:reason]
  end

  private

  def build_client(fetch_estudiante:)
    client = Object.new
    client.define_singleton_method(:enabled?) { true }
    client.define_singleton_method(:fetch_estudiante) { |**| fetch_estudiante }
    client
  end
end
