# frozen_string_literal: true

module Inscripcion
  # Webhook propio del funnel de inscripción (ADR-011). El `notify_url` se elige por pago al crear
  # el enlace de Pagomedios, así que este funnel apunta acá y NO comparte el `payments#webhook`
  # del flujo de deudas: cero riesgo de regresión sobre el cobro de deudas.
  class WebhooksController < ApplicationController
    # Pagomedios hace POST desde sus servidores; no envía authenticity_token.
    skip_before_action :verify_authenticity_token

    def create
      payload = webhook_params.to_h
      Rails.logger.info("[Inscripción Webhook] #{request.request_method} Params: #{payload.to_json}")

      unless autenticado?(payload)
        return browser_callback? ? redirigir_al_resultado : head(:forbidden)
      end

      procesar_notificacion(payload)

      browser_callback? ? redirigir_al_resultado : head(:ok)
    end

    private

    def autenticado?(payload)
      WebhookVerifier.authenticate!(request: request, payload: payload)
      true
    rescue WebhookVerifier::UnauthorizedError => e
      Rails.logger.warn("[Inscripción Webhook] Solicitud rechazada desde #{request.remote_ip}: #{e.reason}")
      false
    end

    def procesar_notificacion(payload)
      if referencia.blank? || payload[:status].blank?
        Rails.logger.info("[Inscripción Webhook] Notificación sin referencia o sin status; se omite.")
        return
      end

      order = OrderRecorder.apply_webhook!(
        reference: referencia,
        pagomedios_status: payload[:status],
        payload: payload
      )
      return if order.blank?

      Rails.logger.info("[Inscripción Webhook] Orden #{order.reference} actualizada a #{order.status}")

      # Regla 8 de crm-gohighlevel: el reporte al CRM corre async, no dentro de este request.
      CrmReportJob.perform_later(order.reference) if order.needs_crm_report?
    end

    def referencia
      webhook_params[:customValue].presence ||
        webhook_params[:reference].presence ||
        params[:reference].to_s.presence
    end

    # Pagomedios a veces dispara el POST desde el navegador de quien paga. En ese caso no sirve
    # responder 200 en blanco: se le muestra la pantalla de resultado.
    def browser_callback?
      ua = request.user_agent.to_s
      ua.match?(/Mozilla|Chrome|Safari|Firefox|Edg|Opera/i) ||
        request.headers["Sec-Fetch-Mode"] == "navigate" ||
        request.headers["Sec-Fetch-Dest"] == "document"
    end

    def redirigir_al_resultado
      order = OrderRecorder.fetch(referencia)

      if order&.return_token.present?
        redirect_to inscripcion_resultado_path(token: order.return_token), allow_other_host: false
      else
        redirect_to inscripcion_resultado_path(reference: referencia), allow_other_host: false
      end
    end

    def webhook_params
      params.permit(
        :status, :reference, :authorizationCode, :customValue, :clientId,
        :transactionDate, :message, :cardNumber, :cardBrand, :cardHolder,
        :ipAddress, :number, :type, :cardToken, :expiryMonth, :expiryYear,
        :amount, :batch, :invoiceNumber
      )
    end
  end
end
