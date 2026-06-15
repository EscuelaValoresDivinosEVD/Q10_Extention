# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    load_access_confirmation_from_flash
    @document_types = ::Q10::IdentificationTypes.new.all
  end

  def acceder
    redirect_to root_path
  end

  def create
    unless valid_access_params?
      redirect_to root_path(access_form_params), alert: access_validation_error_message
      return
    end

    unless verify_q10_student_access
      redirect_to root_path(access_form_params), alert: q10_access_error_message
      return
    end

    unless load_q10_creditos_for_student
      redirect_to root_path(access_form_params), alert: q10_access_error_message
      return
    end

    continue_url = send_continue_link
    unless continue_url
      redirect_to root_path(access_form_params), alert: "No fue posible enviar el correo de continuación. Verifica la configuración de correo e inténtalo de nuevo."
      return
    end

    redirect_to root_path, flash: access_confirmation_flash(continue_url)
  end

  private

  def load_access_confirmation_from_flash
    @show_email_modal = flash[:show_email_modal].present?
    @confirmation_email = flash[:confirmation_email]
    @continue_url = flash[:continue_url]
  end

  def access_confirmation_flash(continue_url)
    {
      show_email_modal: true,
      confirmation_email: params[:email].to_s.strip,
      continue_url: continue_url
    }
  end

  def access_form_params
    params.permit(:document_type, :document, :email)
  end

  def access_validation_error_message
    doc_type = params[:document_type].to_s.strip
    doc = params[:document].to_s.strip
    email = params[:email].to_s.strip
    types = ::Q10::IdentificationTypes.new

    if doc_type.blank? || doc.blank? || email.blank? || !email.match?(URI::MailTo::EMAIL_REGEXP)
      return "Completa tipo de documento, número de documento y correo para continuar."
    end

    if types.find_by_code(doc_type).blank?
      return "Selecciona un tipo de documento válido."
    end

    unless types.valid_document?(code: doc_type, document: doc)
      return "El número de documento no coincide con el formato del tipo seleccionado."
    end

    "Completa tipo de documento, número de documento y correo para continuar."
  end

  def valid_access_params?
    doc_type = params[:document_type].to_s.strip
    doc = params[:document].to_s.strip
    email = params[:email].to_s.strip
    types = ::Q10::IdentificationTypes.new

    doc_type.present? &&
      types.find_by_code(doc_type).present? &&
      types.valid_document?(code: doc_type, document: doc) &&
      doc.present? &&
      email.present? &&
      email.match?(URI::MailTo::EMAIL_REGEXP)
  end

  def verify_q10_student_access
    return true unless q10_student_verification_enabled?

    result = ::Q10::StudentAccessVerifier.new.verify!(
      numero_identificacion: params[:document].to_s.strip,
      email: params[:email].to_s.strip,
      codigo_tipo_identificacion: params[:document_type].to_s.strip
    )

    if result[:valid]
      @q10_estudiante = result[:estudiante]
      @q10_access_error = nil
      return true
    end

    @q10_access_error = result[:reason]
    @q10_access_error_detail = result[:detail]
    false
  end

  def load_q10_creditos_for_student
    numero_identificacion = params[:document].to_s.strip
    return true unless q10_student_verification_enabled?
    return true if skip_q10_creditos_check?

    result = ::Q10::ApiClient.new.fetch_creditos(numero_identificacion: numero_identificacion)
    @q10_creditos = result[:data]
    Rails.logger.info("[Q10] Créditos consultados para identificación #{numero_identificacion}: #{Array(@q10_creditos).size} encontrados.")

    if Array(@q10_creditos).any?
      @q10_access_error = nil
      true
    else
      @q10_access_error = :no_creditos
      false
    end
  rescue ::Q10::ApiClient::Error => e
    Rails.logger.error("[Q10] Error consultando créditos para identificación #{numero_identificacion}: #{e.message}")
    @q10_access_error = :api_error
    @q10_access_error_detail = e.message
    false
  end

  def q10_student_verification_enabled?
    ::Q10::ApiClient.new.enabled?
  end

  def skip_q10_creditos_check?
    ENV["Q10_SKIP_CREDITOS_CHECK"] == "true"
  end

  def q10_access_error_message
    case @q10_access_error
    when :email_mismatch
      "El correo ingresado no coincide con el registrado en Q10 para este documento."
    when :document_type_mismatch
      "El tipo de documento seleccionado no coincide con el registrado en Q10 para este estudiante."
    when :missing_document_type
      "El estudiante está registrado en Q10, pero no tiene un tipo de identificación asociado. Contacta a soporte."
    when :missing_email
      "El estudiante está registrado en Q10, pero no tiene un correo asociado. Contacta a soporte."
    when :not_found
      "No encontramos un estudiante con ese número de identificación en Q10."
    when :no_creditos
      "El estudiante está registrado, pero no encontramos créditos activos en Q10."
    when :api_error
      if Rails.env.development?
        "No fue posible conectar con Q10. Verifica Q10_SUBSCRIPTION_KEY y Q10_API_KEY en .env."
      else
        "No fue posible consultar Q10 en este momento. Intenta de nuevo más tarde."
      end
    else
      "No fue posible validar tus datos en Q10. Intenta de nuevo."
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
