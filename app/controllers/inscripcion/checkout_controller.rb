# frozen_string_literal: true

module Inscripcion
  # Funnel público de inscripción: confirmación del curso + opciones + datos de facturación,
  # todo en una sola pantalla de checkout (ADR-010: esta página cierra la compra, no la vende —
  # el prospecto llega ya decidido desde un sitio externo).
  #
  # Sin login ni token firmado, a diferencia del flujo de deudas (/continuar + Q10::LinkToken).
  class CheckoutController < ApplicationController
    def show
      cargar_pantalla or return

      @opcion_seleccionada = params[:opcion].to_s.presence
      @billing = {}
    end

    def create
      @course_code = params[:codigo].to_s
      @opcion_seleccionada = params[:opcion_code].to_s.presence
      @billing = billing_params

      resultado = OrderCreator.new(
        course_code: @course_code,
        option_code: @opcion_seleccionada,
        billing: @billing,
        notify_url: notify_url_inscripcion,
        return_url_builder: ->(order) { inscripcion_resultado_url(token: order.return_token) }
      ).call

      if resultado.exito?
        redirect_to resultado.payment_url, allow_other_host: true
      else
        Rails.logger.warn("[Inscripción] Checkout no completado (#{resultado.motivo}): #{resultado.error}")
        volver_al_formulario(resultado)
      end
    end

    # Retorno del navegador tras pagar. Solo lectura: el webhook es la fuente de verdad del
    # resultado (regla 4), así que acá puede aparecer todavía como "pendiente".
    def result
      @order = OrderRecorder.fetch_by_return_token(params[:token].to_s.presence) ||
               OrderRecorder.fetch(params[:reference].to_s.presence)

      render :resultado
    end

    private

    # Carga curso + disponibilidad + opciones. Devuelve false (y ya renderizó) si la pantalla no
    # puede mostrarse: Q10 caído, curso inexistente, cerrado o sin matrícula en línea.
    def cargar_pantalla
      @course_code = params[:codigo].to_s
      @catalog = ::Q10::CourseCatalog.new
      @curso = @catalog.find_by_code(@course_code)

      if @curso.blank?
        # Sin caché y con Q10 caído no se puede afirmar nada sobre la disponibilidad: es un estado
        # de error, no un "no existe" (que sería mentirle al usuario).
        if @catalog.error? || @catalog.deshabilitado?
          render :error_disponibilidad, status: :service_unavailable
        else
          render :no_encontrado, status: :not_found
        end
        return false
      end

      # Regla 1: curso cerrado o sin matrícula en línea = no accesible (mismo trato que 404).
      unless @catalog.visible?(@curso)
        render :no_encontrado, status: :not_found
        return false
      end

      @cupos_disponibles = @catalog.cupos_disponibles(@curso)
      @con_cupos = @catalog.cupos?(@curso)                       # regla 2
      @opciones = PricingSource.opciones(course_code: @course_code)
      @tipos_identificacion = ::Q10::IdentificationTypes.new.all
      true
    end

    def volver_al_formulario(resultado)
      cargar_pantalla or return

      flash.now[:alert] = resultado.error
      render :show, status: :unprocessable_entity
    end

    def notify_url_inscripcion
      secret = ENV["INSCRIPCION_WEBHOOK_SECRET"].presence

      secret.present? ? inscripcion_webhook_url(webhook_secret: secret) : inscripcion_webhook_url
    end

    def billing_params
      params.permit(*OrderCreator::CAMPOS_FACTURACION).to_h.symbolize_keys
    end
  end
end
