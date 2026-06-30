# frozen_string_literal: true

module Admin
  class PaymentsController < ApplicationController
    before_action :require_admin_access
    before_action :set_payment, only: :show

    def index
      @payments = Payment.order(created_at: :desc)
      @status_counts = Payment.group(:status).count
      @q10_pending_report_count = Payment.q10_pending_report.count
      @q10_pending_payments = Payment.q10_pending_report.order(created_at: :desc).limit(10)
    end

    def show
    end

    private

    def set_payment
      @payment = Payment.find(params[:id])
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
