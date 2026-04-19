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

    @show_email_modal = true
    @confirmation_email = params[:email].to_s.strip
    render :index
  end

  private

  def valid_access_params?
    doc_type = params[:document_type].to_s.strip
    doc = params[:document].to_s.strip
    email = params[:email].to_s.strip

    doc_type.present? && doc.present? && email.present? && email.match?(URI::MailTo::EMAIL_REGEXP)
  end
end
