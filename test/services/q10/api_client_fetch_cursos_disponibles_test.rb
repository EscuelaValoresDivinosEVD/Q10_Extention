# frozen_string_literal: true

require "test_helper"

class Q10::ApiClientFetchCursosDisponiblesTest < ActiveSupport::TestCase
  CURSO_Q10 = {
    "Consecutivo" => 1,
    "Codigo" => "EJO1",
    "Nombre" => "Desarrollo de aplicaciones móviles",
    "Cupo_maximo" => 10,
    "Cantidad_estudiantes_matriculados" => 3,
    "Consecutivo_periodo" => 1,
    "Nombre_periodo" => "2025-01-01",
    "Fecha_inicio" => "2025-01-01T12:00:00Z",
    "Fecha_fin" => "2025-06-30T12:00:00Z",
    "Estado" => "Abierto",
    "Aplica_matricula_en_linea" => true
  }.freeze

  def build_client(body:, code: "200")
    fake_response = Object.new.tap do |response|
      response.define_singleton_method(:code) { code }
      response.define_singleton_method(:body) { body }
      response.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess && code == "200" }
    end

    client = Q10::ApiClient.new(config: Rails.application.config_for(:q10).deep_symbolize_keys.merge(enabled: true))
    client.define_singleton_method(:perform_get) do |uri, _headers|
      @captured_uri = uri
      fake_response
    end
    client.define_singleton_method(:captured_uri) { @captured_uri }
    client
  end

  test "fetch_cursos_disponibles hace GET a /cursos con Limit y Offset" do
    client = build_client(body: [ CURSO_Q10 ].to_json)

    result = client.fetch_cursos_disponibles(limit: 50, offset: 1)

    assert_equal "https://api.q10.com/v1/cursos?Limit=50&Offset=1", client.captured_uri.to_s
    assert result[:success]
    assert_equal "EJO1", result[:data].first["Codigo"]
  end

  test "fetch_cursos_disponibles agrega el filtro Estado cuando se envía" do
    client = build_client(body: [ CURSO_Q10 ].to_json)

    client.fetch_cursos_disponibles(limit: 10, offset: 1, estado: "Abierto")

    assert_equal "https://api.q10.com/v1/cursos?Limit=10&Offset=1&Estado=Abierto", client.captured_uri.to_s
  end

  test "fetch_cursos_disponibles descarta elementos que no son objetos" do
    client = build_client(body: [ CURSO_Q10, "basura", nil ].to_json)

    result = client.fetch_cursos_disponibles

    assert_equal 1, result[:data].size
  end

  test "fetch_cursos_disponibles falla si la integración Q10 está deshabilitada" do
    client = Q10::ApiClient.new(config: Rails.application.config_for(:q10).deep_symbolize_keys.merge(enabled: false))

    error = assert_raises(Q10::ApiClient::Error) { client.fetch_cursos_disponibles }
    assert_match(/deshabilitada/, error.message)
  end

  test "fetch_cursos_disponibles levanta error ante respuesta no exitosa de Q10" do
    client = build_client(body: '{"error":"boom"}', code: "500")

    assert_raises(Q10::ApiClient::Error) { client.fetch_cursos_disponibles }
  end
end
