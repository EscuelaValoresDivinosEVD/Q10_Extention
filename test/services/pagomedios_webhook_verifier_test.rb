# frozen_string_literal: true

require "test_helper"

class PagomediosWebhookVerifierTest < ActiveSupport::TestCase
  setup do
    @original_secret = ENV["PAGOMEDIOS_WEBHOOK_SECRET"]
    ENV["PAGOMEDIOS_WEBHOOK_SECRET"] = "test-webhook-secret"
    @payment = Payment.create!(
      reference: "CLEV-WEBHOOK-TEST",
      status: "pending",
      amount: 116.0,
      currency: "USD"
    )
    @payload = {
      status: "1",
      customValue: "CLEV-WEBHOOK-TEST",
      authorizationCode: "243424",
      amount: "116.00"
    }
  end

  teardown do
    ENV["PAGOMEDIOS_WEBHOOK_SECRET"] = @original_secret
  end

  test "autentica webhook con secreto válido y pago conocido" do
    request = build_request(webhook_secret: "test-webhook-secret")

    assert PagomediosWebhookVerifier.authenticate!(request: request, payload: @payload)
  end

  test "rechaza webhook con secreto inválido" do
    request = build_request(webhook_secret: "wrong-secret")

    error = assert_raises(PagomediosWebhookVerifier::UnauthorizedError) do
      PagomediosWebhookVerifier.authenticate!(request: request, payload: @payload)
    end

    assert_equal "invalid_webhook_secret", error.reason
  end

  test "rechaza webhook para pago inexistente" do
    request = build_request(webhook_secret: "test-webhook-secret")

    error = assert_raises(PagomediosWebhookVerifier::UnauthorizedError) do
      PagomediosWebhookVerifier.authenticate!(
        request: request,
        payload: @payload.merge(customValue: "CLEV-MISSING")
      )
    end

    assert_equal "unknown_payment", error.reason
  end

  test "rechaza webhook sin secreto configurado" do
    ENV["PAGOMEDIOS_WEBHOOK_SECRET"] = ""
    request = build_request(webhook_secret: "test-webhook-secret")

    error = assert_raises(PagomediosWebhookVerifier::UnauthorizedError) do
      PagomediosWebhookVerifier.authenticate!(request: request, payload: @payload)
    end

    assert_equal "missing_webhook_secret_config", error.reason
  end

  test "rechaza webhook con monto distinto al registrado" do
    request = build_request(webhook_secret: "test-webhook-secret")

    error = assert_raises(PagomediosWebhookVerifier::UnauthorizedError) do
      PagomediosWebhookVerifier.authenticate!(
        request: request,
        payload: @payload.merge(amount: "999.00")
      )
    end

    assert_equal "amount_mismatch", error.reason
  end

  private

  def build_request(webhook_secret:)
    ActionDispatch::TestRequest.create.tap do |request|
      request.request_method = "POST"
      request.path_parameters = { webhook_secret: webhook_secret }
    end
  end
end
