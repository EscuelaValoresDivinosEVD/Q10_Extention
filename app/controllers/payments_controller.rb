# frozen_string_literal: true

class PaymentsController < ApplicationController
  # Pagomedios hace POST desde sus servidores; no envía authenticity_token
  skip_before_action :verify_authenticity_token, only: [ :webhook, :return ]

  def new
    # Formulario manual de prueba (/pagar)
  end

  def show
    @reference = params[:reference].to_s.presence
    @session = PaymentSessionStore.fetch(@reference) if @reference.present?
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

    reference = build_reference
    description = params[:description].presence || default_description(reference)

    result = ::PagomediosService.new.create_payment(
      amount: amount,
      currency: params[:currency].presence || "USD",
      reference: reference,
      description: description,
      notify_url: payments_webhook_url,
      return_url: payment_return_url(reference: reference)
    )

    unless result[:success]
      record_payment_failure(reference, amount, description, result[:error] || "No se pudo generar el enlace de pago.")
      return render_payment_error(result[:error] || "No se pudo generar el enlace de pago.")
    end

    session_payload = build_session_payload(reference, amount, description, result)
    PaymentSessionStore.save(reference, session_payload)
    PaymentRecorder.record_pending!(reference: reference, attrs: payment_record_attrs(session_payload, result))

    redirect_to result[:payment_url], allow_other_host: true
  rescue ::PagomediosService::Error => e
    record_payment_failure(reference, amount, description, e.message) if defined?(reference) && reference.present?
    render_payment_error(e.message)
  end

  # Retorno del navegador tras pagar (return_url de Pagomedios).
  def return
    reference = process_pagomedios_notification
    finish_browser_payment(reference)
  end

  # Webhook Pagomedios (notify_url): notificación servidor; a veces el navegador llega aquí tras pagar.
  def webhook
    reference = process_pagomedios_notification

    if browser_callback?
      finish_browser_payment(reference)
    else
      head :ok
    end
  end

  private

  def process_pagomedios_notification
    payload = webhook_params.to_h
    Rails.logger.info "[Pagomedios Webhook] #{request.request_method} Params: #{payload.to_json}"

    reference = payload[:customValue].presence || payload[:reference].presence || params[:reference].to_s.presence
    return reference if reference.blank?

    if payload[:status].blank?
      Rails.logger.info "[Pagomedios] Callback sin status para #{reference}; se usa el estado guardado."
      return reference
    end

    status = map_pagomedios_status(payload[:status])
    session = PaymentSessionStore.update_status(reference, status: status, webhook_payload: payload)
    PaymentRecorder.apply_webhook!(reference: reference, status: status, webhook_payload: payload)
    Rails.logger.info "[Pagomedios Webhook] Sesión #{reference} actualizada a #{status}"

    ::Q10::ReportOrchestrator.report_and_record!(session) if status == "authorized"
    reference
  end

  def post_payment_redirect_url(reference)
    session = PaymentSessionStore.fetch(reference)

    if session&.dig(:return_token).present?
      url_params = { token: session[:return_token] }

      case session[:status]
      when "authorized"
        url_params[:payment_success] = "1"
        url_params[:payment_ref] = reference if reference.present?
        url_params[:consecutivo_credito] = session[:consecutivo_credito] if session[:consecutivo_credito].present?
        url_params[:q10_pending] = "1" unless session[:q10_reported]
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
    @session = PaymentSessionStore.fetch(reference) || {}
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
