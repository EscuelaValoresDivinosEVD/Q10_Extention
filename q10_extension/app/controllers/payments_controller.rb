# frozen_string_literal: true

class PaymentsController < ApplicationController
  # Pagomedios hace POST desde sus servidores; no envía authenticity_token
  skip_before_action :verify_authenticity_token, only: [ :webhook ]

  def new
    # Formulario para ingresar el monto
  end

  def create
    amount = params[:amount].to_s.tr(",", ".")
    if amount.blank? || amount.to_f <= 0
      flash.now[:alert] = "Ingresa un monto válido mayor a 0."
      render :new, status: :unprocessable_entity
      return
    end

    result = ::PagomediosService.new.create_payment(
      amount: amount,
      currency: params[:currency].presence || "USD",
      reference: params[:reference].presence,
      description: params[:description].presence,
      notify_url: payments_webhook_url
    )

    if result[:success]
      @payment_url = result[:payment_url]
      @payment_id = result[:id]
      @amount = result[:amount]
      render :checkout
    else
      flash.now[:alert] = result[:error] || "No se pudo generar el enlace de pago."
      render :new, status: :unprocessable_entity
    end
  rescue ::PagomediosService::Error => e
    flash.now[:alert] = e.message
    render :new, status: :unprocessable_entity
  end

  # Webhook: Pagomedios envía POST cuando el pago cambia de estado.
  # Parámetros típicos: status, reference, authorizationCode, customValue, clientId,
  # transactionDate, message, cardNumber, cardBrand, cardHolder, etc.
  # status: 0 = Pendiente, 1 = Autorizada, 2 = Rechazada, 3 = Reversada
  def webhook
    Rails.logger.info "[Pagomedios Webhook] Params: #{webhook_params.to_h.to_json}"

    # Aquí puedes actualizar un modelo Payment, enviar email, etc.
    # Ejemplo: Payment.find_by(reference: params[:reference])&.update!(status: params[:status], ...)

    head :ok
  end

  private

  def webhook_params
    params.permit(
      :status, :reference, :authorizationCode, :customValue, :clientId,
      :transactionDate, :message, :cardNumber, :cardBrand, :cardHolder,
      :ipAddress, :number, :type, :cardToken, :expiryMonth, :expiryYear
    )
  end
end
