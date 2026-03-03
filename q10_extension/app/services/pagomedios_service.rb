# frozen_string_literal: true

# Servicio para integrar con Pagomedios API v2
# Documentación: https://docs.abitmedia.cloud/pagomedios-referencia-api-v2/
# Ajusta el endpoint y el body según la documentación oficial (Solicitudes de pago / Links de pago)
class PagomediosService
  BASE_URL = "https://services.abitmedia.cloud/pagomedios-v2"

  class Error < StandardError; end
  class ApiError < Error; end

  def initialize
    @token = ENV.fetch("PAGOMEDIOS_API_TOKEN", nil)
    raise Error, "PAGOMEDIOS_API_TOKEN no está configurado en .env" if @token.blank?
  end

  # Crea una solicitud de pago o link de pago y devuelve la URL para que el usuario pague.
  # @param amount [Float, String] Monto a cobrar (ej: 25.50)
  # @param currency [String] Código ISO de moneda (ej: "USD")
  # @param reference [String] Referencia única del pago (opcional)
  # @param description [String] Descripción del pago (opcional)
  # @return [Hash] { success: true, payment_url: "...", id: "..." } o { success: false, error: "..." }
  def create_payment(amount:, currency: "USD", reference: nil, description: nil)
    reference ||= "PAGO-#{Time.current.to_i}"
    description ||= "Pago"

    # Monto en centavos/unidades mínimas si la API lo requiere (revisar documentación)
    amount_cents = (amount.to_f * 100).to_i

    body = {
      monto: amount.to_f,
      monto_centavos: amount_cents,
      moneda: currency,
      referencia: reference,
      descripcion: description
    }.compact

    # Endpoint típico para "Solicitudes de pago" o "Links de pago"
    # Verificar en docs: https://docs.abitmedia.cloud/pagomedios-referencia-api-v2/
    endpoint = "#{BASE_URL}/solicitudes-pago"
    response = post(endpoint, body)

    parse_payment_response(response, amount)
  rescue ApiError => e
    { success: false, error: e.message }
  rescue Error => e
    { success: false, error: e.message }
  end

  private

  def post(path, body)
    uri = URI(path)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = 15
    http.read_timeout = 25

    request = Net::HTTP::Post.new(uri.request_uri)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{@token}"
    request.body = body.to_json

    response = http.request(request)
    result = { code: response.code.to_i, body: response.body }

    unless response.is_a?(Net::HTTPSuccess)
      raise ApiError, "Pagomedios API error #{response.code}: #{response.body}"
    end

    result
  end

  def parse_payment_response(response, amount)
    data = JSON.parse(response[:body])
    # Ajustar según la estructura real de la respuesta de Pagomedios (docs: Links de pago / Solicitudes de pago)
    payment_url = data["url_pago"] || data["payment_url"] || data["url"] || data.dig("data", "url_pago")
    id = data["id"] || data["solicitud_id"] || data.dig("data", "id")

    if payment_url.present?
      { success: true, payment_url: payment_url, id: id, amount: amount }
    else
      # Si tu API devuelve otro campo para la URL, añádelo arriba o ajusta en config
      { success: false, error: "La API no devolvió URL de pago. Revisa el formato en la documentación.", raw: data }
    end
  rescue JSON::ParserError
    raise ApiError, "Respuesta inválida de Pagomedios: #{response[:body]}"
  end
end
