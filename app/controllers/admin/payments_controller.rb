# frozen_string_literal: true

module Admin
  class PaymentsController < ApplicationController
    before_action :require_admin_access
    before_action :set_payment, only: :show
    before_action :set_date_filters, only: %i[index export]

    def index
      return if reject_invalid_date_filters?

      load_payments_index
    end

    def export
      error = date_filter_error(require_both: true)
      if error
        redirect_to admin_payments_path(
          fecha_desde: params[:fecha_desde],
          fecha_hasta: params[:fecha_hasta]
        ), alert: error
        return
      end

      payments = filtered_payments.order(created_at: :desc)
      exporter = Admin::PaymentsExcelExporter.new(payments)

      send_data(
        exporter.to_stream,
        filename: exporter.filename,
        type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        disposition: "attachment"
      )
    end

    def show
    end

    private

    def set_payment
      @payment = Payment.find(params[:id])
    end

    def set_date_filters
      @fecha_desde = parse_filter_date(params[:fecha_desde])
      @fecha_hasta = parse_filter_date(params[:fecha_hasta])
    end

    def reject_invalid_date_filters?
      error = date_filter_error(require_both: date_filter_attempted?)
      return false unless error

      flash.now[:alert] = error
      @payments = Payment.none
      @status_counts = {}
      @q10_pending_report_count = 0
      @q10_pending_payments = Payment.none
      true
    end

    def date_filter_attempted?
      params[:fecha_desde].present? || params[:fecha_hasta].present?
    end

    def date_filter_error(require_both:)
      if require_both && (@fecha_desde.blank? || @fecha_hasta.blank?)
        return "Debes indicar la fecha desde y la fecha hasta."
      end

      if @fecha_desde.present? && @fecha_hasta.present? && @fecha_hasta < @fecha_desde
        return "La fecha hasta no puede ser menor que la fecha desde."
      end

      nil
    end

    def load_payments_index
      @payments = filtered_payments.order(created_at: :desc)
      @status_counts = filtered_payments.group(:status).count
      @q10_pending_report_count = filtered_payments.q10_pending_report.count
      @q10_pending_payments = filtered_payments.q10_pending_report.order(created_at: :desc).limit(10)
    end

    def filtered_payments
      Payment.created_between(@fecha_desde, @fecha_hasta)
    end

    def parse_filter_date(value)
      return if value.blank?

      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def require_admin_access
      if ENV["ADMIN_PASSWORD"].blank?
        raise ActionController::RoutingError, "Not Found" if Rails.env.production?

        return
      end

      authenticate_or_request_with_http_basic("Admin CLEV") do |username, password|
        admin_username = ENV.fetch("ADMIN_USERNAME", "admin")
        admin_password = ENV["ADMIN_PASSWORD"]

        secure_compare(username, admin_username) && secure_compare(password, admin_password)
      end
    end

    def secure_compare(given, expected)
      ActiveSupport::SecurityUtils.secure_compare(given.to_s, expected.to_s)
    rescue ArgumentError
      false
    end
  end
end
