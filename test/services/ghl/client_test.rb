# frozen_string_literal: true

require "test_helper"

class Ghl::ClientTest < ActiveSupport::TestCase
  CONFIG = {
    enabled: true,
    base_url: "https://services.leadconnectorhq.com",
    api_version: "v3",
    token: "pit-token-de-prueba",
    location_id: "loc_123",
    source: "CLEV inscripción",
    open_timeout: 10,
    read_timeout: 25
  }.freeze

  def fake_response(code:, body:)
    Object.new.tap do |response|
      response.define_singleton_method(:code) { code.to_s }
      response.define_singleton_method(:body) { body }
    end
  end

  def client_con(code:, body:, config: CONFIG)
    capturado = {}
    client = Ghl::Client.new(config: config)
    respuesta = fake_response(code: code, body: body)
    client.define_singleton_method(:post) do |url, payload|
      capturado[:url] = url
      capturado[:body] = payload
      respuesta
    end
    client.define_singleton_method(:capturado) { capturado }
    client
  end

  test "upsert_contact hace POST a /contacts/upsert y devuelve el id del contacto" do
    body = { "contact" => { "id" => "cnt_7Xk2" }, "new" => true, "traceId" => "trace-1" }.to_json
    client = client_con(code: 200, body: body)

    resultado = client.upsert_contact(firstName: "Valentina", email: "v@correo.com", country: "EC")

    assert_equal "https://services.leadconnectorhq.com/contacts/upsert", client.capturado[:url]
    assert_equal "cnt_7Xk2", resultado[:contact_id]
    assert_equal true, resultado[:new]
    assert_equal "trace-1", resultado[:trace_id]
  end

  test "upsert_contact agrega el locationId obligatorio y descarta campos vacíos" do
    client = client_con(code: 200, body: { "contact" => { "id" => "cnt_1" } }.to_json)

    client.upsert_contact(firstName: "Valentina", country: nil, city: "")

    enviado = client.capturado[:body]
    assert_equal "loc_123", enviado[:locationId]
    assert_not enviado.key?(:country), "Un país no resuelto no debe viajar como nil"
    assert_not enviado.key?(:city)
  end

  test "upsert_contact NO envía tags (sobrescribirían los tags previos del contacto)" do
    client = client_con(code: 200, body: { "contact" => { "id" => "cnt_1" } }.to_json)

    client.upsert_contact(firstName: "Valentina", email: "v@correo.com")

    assert_not client.capturado[:body].key?(:tags)
  end

  test "add_tags hace POST a /contacts/:id/tags y acepta 201 como éxito" do
    client = client_con(code: 201, body: { "tags" => [ "ayurveda-2026" ] }.to_json)

    resultado = client.add_tags(contact_id: "cnt_7Xk2", tags: [ "ayurveda-2026" ])

    assert_equal "https://services.leadconnectorhq.com/contacts/cnt_7Xk2/tags", client.capturado[:url]
    assert_equal({ tags: [ "ayurveda-2026" ] }, client.capturado[:body])
    assert_equal [ "ayurveda-2026" ], resultado[:tags]
  end

  test "add_tags exige contacto y al menos un tag" do
    client = client_con(code: 201, body: "{}")

    assert_raises(Ghl::Client::Error) { client.add_tags(contact_id: nil, tags: [ "x" ]) }
    assert_raises(Ghl::Client::Error) { client.add_tags(contact_id: "cnt_1", tags: []) }
  end

  test "un 401 levanta UnauthorizedError con el detalle del CRM" do
    client = client_con(code: 401, body: { "message" => "Invalid token" }.to_json)

    error = assert_raises(Ghl::Client::UnauthorizedError) do
      client.upsert_contact(email: "v@correo.com")
    end

    assert_match(/HTTP 401/, error.message)
    assert_match(/Invalid token/, error.message)
  end

  test "un 422 levanta Error" do
    client = client_con(code: 422, body: { "message" => "email inválido" }.to_json)

    assert_raises(Ghl::Client::Error) { client.upsert_contact(email: "no-sirve") }
  end

  test "el cliente está deshabilitado si falta token o location" do
    assert_not Ghl::Client.new(config: CONFIG.merge(token: nil)).enabled?
    assert_not Ghl::Client.new(config: CONFIG.merge(location_id: nil)).enabled?
    assert_not Ghl::Client.new(config: CONFIG.merge(enabled: false)).enabled?
    assert Ghl::Client.new(config: CONFIG).enabled?
  end

  test "llamar al cliente deshabilitado levanta un error explícito" do
    client = Ghl::Client.new(config: CONFIG.merge(enabled: false))

    error = assert_raises(Ghl::Client::Error) { client.upsert_contact(email: "v@correo.com") }
    assert_match(/deshabilitada/, error.message)
  end

  test "en el entorno de test la integración viene deshabilitada por configuración" do
    assert_not Ghl::Client.new.enabled?
  end
end
