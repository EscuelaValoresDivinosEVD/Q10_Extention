# frozen_string_literal: true

class HomeController < ApplicationController
  def index
  end

  def create
    unless valid_access_params?
      flash.now[:alert] = "Completa tipo de documento, número de documento y correo para continuar."
      render :index, status: :unprocessable_entity
      return
    end

    unless load_q10_creditos_for_student
      flash.now[:alert] = q10_access_error_message
      render :index, status: :unprocessable_entity
      return
    end

    continue_url = send_continue_link
    unless continue_url
      flash.now[:alert] = "No fue posible enviar el correo de continuación. Verifica la configuración de correo e inténtalo de nuevo."
      render :index, status: :unprocessable_entity
      return
    end

    @show_email_modal = true
    @confirmation_email = params[:email].to_s.strip
    @continue_url = continue_url
    render :index
  end

  private

  def valid_access_params?
    doc_type = params[:document_type].to_s.strip
    doc = params[:document].to_s.strip
    email = params[:email].to_s.strip

    doc_type.present? && doc.present? && email.present? && email.match?(URI::MailTo::EMAIL_REGEXP)
  end

  def load_q10_creditos_for_student
    numero_identificacion = params[:document].to_s.strip
    client = ::Q10::ApiClient.new
    return true unless client.enabled?

    result = client.fetch_creditos(numero_identificacion: numero_identificacion)
    @q10_creditos = result[:data]
    Rails.logger.info("[Q10] Créditos consultados para identificación #{numero_identificacion}: #{Array(@q10_creditos).size} encontrados.")

    if Array(@q10_creditos).any?
      @q10_access_error = nil
      true
    else
      @q10_access_error = :not_found
      false
    end
  rescue ::Q10::ApiClient::Error => e
    Rails.logger.error("[Q10] Error consultando créditos para identificación #{numero_identificacion}: #{e.message}")
    return true if ENV["Q10_SKIP_CREDITOS_CHECK"] == "true"

    @q10_access_error = :api_error
    @q10_access_error_detail = e.message
    false
  end

  def q10_access_error_message
    case @q10_access_error
    when :api_error
      if Rails.env.development?
        "No fue posible conectar con Q10. Verifica Q10_SUBSCRIPTION_KEY y Q10_API_KEY en .env."
      else
        "No fue posible consultar Q10 en este momento. Intenta de nuevo más tarde."
      end
    else
      "No encontramos un estudiante con ese número de identificación en Q10."
    end
  end

  def send_continue_link
    token = ::Q10::LinkToken.generate(
      {
        numero_identificacion: params[:document].to_s.strip,
        email: params[:email].to_s.strip
      }
    )
    continue_url = q10_continue_url(token: token)
    StudentAccessMailer.continue_process(email: params[:email].to_s.strip, continue_url: continue_url).deliver_now
    continue_url
  rescue StandardError => e
    Rails.logger.error("[Q10] Falló envío de correo: #{e.message}")
    nil
  end
end
