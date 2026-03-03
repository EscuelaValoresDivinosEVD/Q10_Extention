# frozen_string_literal: true

class PaymentsController < ApplicationController
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
      description: params[:description].presence
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
end
