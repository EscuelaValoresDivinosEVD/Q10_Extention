# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

# Servicio para integrar con Pagomedios API v2
# Documentación: https://docs.abitmedia.cloud/pagomedios-referencia-api-v2/
# OpenAPI: https://api.abitmedia.cloud/pagomedios/v2 (payment-links, payment-requests)
class PagomediosService
  BASE_URL = "https://api.abitmedia.cloud/pagomedios/v2"

  class Error < StandardError; end
  class ApiError < Error; end

  def initialize
    @token = ENV.fetch("PAGOMEDIOS_API_TOKEN", nil)
    raise Error, "PAGOMEDIOS_API_TOKEN no está configurado en .env" if @token.blank?
    Rails.logger.debug "[Pagomedios] Token configurado"
  end

  # Crea una solicitud de pago o link de pago y devuelve la URL para que el usuario pague.
  # @param amount [Float, String] Monto a cobrar (ej: 25.50)
  # @param currency [String] Código ISO de moneda (ej: "USD")
  # @param reference [String] Referencia única del pago (opcional)
  # @param description [String] Descripción del pago (opcional)
  # @param notify_url [String] URL absoluta del webhook
  # @param return_url [String] URL a la que Pagomedios puede redirigir al usuario tras pagar (opcional)
  # @return [Hash] { success: true, payment_url: "...", id: "..." } o { success: false, error: "..." }
  def create_payment(amount:, currency: "USD", reference: nil, description: nil, notify_url: nil, return_url: nil)
    reference ||= "PAGO-#{Time.current.to_i}"
    description ||= "Pago"

    Rails.logger.info "[Pagomedios] create_payment params: amount=#{amount}, currency=#{currency}, reference=#{reference}, description=#{description}"

    amount_f = amount.to_f.round(2)
    # API requiere: amount = amount_with_tax + amount_without_tax + tax_value (todos con 2 decimales)
    body = {
      integration: true,
      generate_invoice: 0,
      description: description.to_s,
      amount: amount_f,
      amount_with_tax: 0,
      amount_without_tax: amount_f,
      tax_value: 0,
      has_cards: 1,
      has_de_una: 0,
      has_paypal: 0,
      has_safetypay: false,
      custom_value: reference.to_s
    }
    body[:notify_url] = notify_url if notify_url.present?
    body[:return_url] = return_url if return_url.present?

    endpoint = "#{BASE_URL}/payment-links"
    Rails.logger.info "[Pagomedios] POST #{endpoint} body=#{body.to_json}"

    response = post(endpoint, body)

    parse_payment_response(response, amount)
  rescue ApiError => e
    Rails.logger.error "[Pagomedios] ApiError: #{e.message}"
    { success: false, error: e.message }
  rescue Error => e
    Rails.logger.error "[Pagomedios] Error: #{e.message}"
    { success: false, error: e.message }
  end

  private

  def post(path, body)
    uri = URI(path)
    Rails.logger.info "[Pagomedios] Request: #{uri.scheme}://#{uri.host}:#{uri.port}#{uri.request_uri}"

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

    Rails.logger.info "[Pagomedios] Response: code=#{response.code}, body=#{response.body}"

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error "[Pagomedios] API error #{response.code}: #{response.body}"
      raise ApiError, "Pagomedios API error #{response.code}: #{response.body}"
    end

    result
  end

  def parse_payment_response(response, amount)
    data = JSON.parse(response[:body])
    Rails.logger.info "[Pagomedios] Parsed response: #{data.inspect}"

    # SuccessPaymentRequest: data.data.url, data.data.token
    payment_url = data.dig("data", "url") || data["url_pago"] || data["payment_url"] || data["url"]
    id = data.dig("data", "token") || data["id"] || data["solicitud_id"]

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
