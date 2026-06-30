# frozen_string_literal: true

class PaymentsController < ApplicationController
  # Pagomedios hace POST desde sus servidores; no envía authenticity_token
  skip_before_action :verify_authenticity_token, only: [ :webhook, :return ]

  def new
    # Formulario manual de prueba (/pagar)
  end

  def show
    @reference = params[:reference].to_s.presence
    @payment = PaymentRecorder.fetch(@reference) if @reference.present?
  end

  def create
    amount = normalized_amount
    if amount.blank? || amount.to_f <= 0
      return render_payment_error("Ingresa un monto válido mayor a 0.")
    end

    if cuota_payment? && selected_cuotas.empty?
      return render_payment_error("Selecciona al menos una cuota para continuar con el pago.")
    end

    if cuota_payment? && !valid_pending_cuota_selection?
      return render_payment_error("Debes pagar desde la cuota más vencida y en orden consecutivo.")
    end

    if cuota_payment? && blocked_cuotas_selected?
      return render_payment_error(
        "Una o más cuotas seleccionadas tienen un pago aprobado pendiente de registro en Q10. " \
        "Espera unos minutos e intenta de nuevo."
      )
    end

    reference = build_reference
    description = params[:description].presence || default_description(reference)

    result = ::PagomediosService.new.create_payment(
      amount: amount,
      currency: params[:currency].presence || "USD",
      reference: reference,
      description: description,
      notify_url: pagomedios_notify_url,
      return_url: payment_return_url(reference: reference)
    )

    unless result[:success]
      record_payment_failure(reference, amount, description, result[:error] || "No se pudo generar el enlace de pago.")
      return render_payment_error(result[:error] || "No se pudo generar el enlace de pago.")
    end

    session_payload = build_session_payload(reference, amount, description, result)
    PaymentRecorder.record_pending!(reference: reference, attrs: payment_record_attrs(session_payload, result))

    redirect_to result[:payment_url], allow_other_host: true
  rescue ::PagomediosService::Error => e
    record_payment_failure(reference, amount, description, e.message) if defined?(reference) && reference.present?
    render_payment_error(e.message)
  end

  # Retorno del navegador tras pagar (return_url de Pagomedios). Solo lectura.
  def return
    finish_browser_payment(notification_reference)
  end

  # Webhook Pagomedios (notify_url): notificaciones POST verificadas mutan la BD.
  # Pagomedios puede enviar el POST desde el navegador del pagador; en ese caso
  # también se procesa y luego se muestra la pantalla de confirmación.
  def webhook
    if processable_pagomedios_notification?
      unless authenticate_pagomedios_webhook!
        return browser_callback? ? finish_browser_payment(notification_reference) : head(:forbidden)
      end

      process_pagomedios_notification

      if browser_callback?
        finish_browser_payment(notification_reference)
      else
        head :ok
      end
    else
      finish_browser_payment(notification_reference)
    end
  end

  private

  def authenticate_pagomedios_webhook!
    PagomediosWebhookVerifier.authenticate!(request: request, payload: webhook_params.to_h)
    true
  rescue PagomediosWebhookVerifier::UnauthorizedError => e
    Rails.logger.warn(
      "[Pagomedios Webhook] Solicitud rechazada desde #{request.remote_ip}: #{e.reason}"
    )
    false
  end

  def process_pagomedios_notification
    payload = webhook_params.to_h
    Rails.logger.info "[Pagomedios Webhook] #{request.request_method} Params: #{payload.to_json}"

    reference = notification_reference
    return if reference.blank?

    if payload[:status].blank?
      Rails.logger.info "[Pagomedios] Callback sin status para #{reference}; se omite actualización."
      return
    end

    status = map_pagomedios_status(payload[:status])
    payment = PaymentRecorder.update_status!(reference: reference, status: status, webhook_payload: payload)
    Rails.logger.info "[Pagomedios Webhook] Pago #{reference} actualizado a #{status}"

    ::Q10::ReportOrchestrator.report_and_record!(payment) if payment&.successful?
  end

  def notification_reference
    webhook_params[:customValue].presence ||
      webhook_params[:reference].presence ||
      params[:reference].to_s.presence
  end

  def processable_pagomedios_notification?
    request.post? && webhook_params[:status].present? && notification_reference.present?
  end

  def pagomedios_notify_url
    secret = ENV["PAGOMEDIOS_WEBHOOK_SECRET"].presence
    if secret.present?
      payments_webhook_url(webhook_secret: secret)
    else
      payments_webhook_url
    end
  end

  def post_payment_redirect_url(reference)
    payment = PaymentRecorder.fetch(reference)

    if payment&.return_token.present?
      url_params = { token: payment.return_token }

      case payment.status
      when "authorized"
        url_params[:payment_success] = "1"
        url_params[:payment_ref] = reference if reference.present?
        url_params[:consecutivo_credito] = payment.consecutivo_credito if payment.consecutivo_credito.present?
        url_params[:q10_pending] = "1" unless payment.q10_reported?
      when "rejected", "reversed"
        url_params[:payment_error] = "El pago no fue aprobado. Intenta nuevamente."
      end

      q10_continue_url(url_params)
    else
      payment_result_url(reference: reference.presence || params[:reference])
    end
  end

  def record_payment_failure(reference, amount, description, error_message)
    attrs = payment_record_attrs(
      build_session_payload(reference, amount, description, {}),
      {}
    )
    PaymentRecorder.record_failed!(reference: reference, attrs: attrs, error_message: error_message)
  end

  def payment_record_attrs(session, result)
    {
      amount: session[:amount],
      currency: session[:currency],
      description: session[:description],
      numero_identificacion: session[:numero_identificacion],
      codigo_persona: session[:codigo_persona],
      codigo_estudiante: session[:codigo_estudiante],
      codigo_cajero: session[:codigo_cajero],
      consecutivo_credito: session[:consecutivo_credito],
      cuotas: Array(session[:cuotas]),
      pagomedios_token: result[:id],
      payment_url: result[:payment_url],
      return_token: session[:return_token]
    }
  end

  def browser_callback?
    ua = request.user_agent.to_s
    browser_ua = ua.match?(/Mozilla|Chrome|Safari|Firefox|Edg|Opera/i)
    navigate = request.headers["Sec-Fetch-Mode"] == "navigate" ||
               request.headers["Sec-Fetch-Dest"] == "document"

    browser_ua || navigate
  end

  def finish_browser_payment(reference)
    @payment = PaymentRecorder.fetch(reference)
    @panel_url = post_payment_redirect_url(reference)
    render :complete, layout: "application", status: :ok
  end

  def normalized_amount
    params[:amount].to_s.tr(",", ".")
  end

  def cuota_payment?
    params[:return_token].present? || params[:cuotas].present?
  end

  def selected_cuotas
    Array(params[:cuotas]).flat_map { |value| value.to_s.split(",") }.map(&:strip).reject(&:blank?)
  end

  def valid_pending_cuota_selection?
    order = params[:pending_cuotas_order].to_s.split(",").map(&:strip).reject(&:blank?)
    return true if order.empty?

    CuotaSelection.valid_selection?(order, selected_cuotas)
  end

  def blocked_cuotas_selected?
    PaymentCuotaLock.any_blocked?(
      numero_identificacion: params[:numero_identificacion],
      consecutivo_credito: params[:consecutivo_credito],
      cuota_numbers: selected_cuotas
    )
  end

  def build_reference
    params[:reference].presence || "CLEV-#{Time.current.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(3).upcase}"
  end

  def default_description(reference)
    "Pago CLEV #{reference}"
  end

  def build_session_payload(reference, amount, description, result)
    {
      reference: reference,
      status: "pending",
      amount: amount.to_f.round(2),
      currency: params[:currency].presence || "USD",
      description: description,
      pagomedios_id: result[:id],
      payment_url: result[:payment_url],
      return_token: params[:return_token],
      numero_identificacion: params[:numero_identificacion],
      codigo_persona: params[:codigo_persona],
      codigo_estudiante: params[:codigo_estudiante],
      codigo_cajero: params[:codigo_cajero],
      consecutivo_credito: params[:consecutivo_credito],
      cuotas: selected_cuotas,
      created_at: Time.current.iso8601
    }
  end

  def render_payment_error(message)
    if params[:return_token].present?
      redirect_to q10_continue_path(token: params[:return_token], payment_error: message),
                  allow_other_host: false
    else
      flash.now[:alert] = message
      render :new, status: :unprocessable_entity
    end
  end

  def map_pagomedios_status(raw_status)
    case raw_status.to_s
    when "1" then "authorized"
    when "2" then "rejected"
    when "3" then "reversed"
    else "pending"
    end
  end

  def webhook_params
    params.permit(
      :status, :reference, :authorizationCode, :customValue, :clientId,
      :transactionDate, :message, :cardNumber, :cardBrand, :cardHolder,
      :ipAddress, :number, :type, :cardToken, :expiryMonth, :expiryYear, :amount, :batch
    )
  end
end
