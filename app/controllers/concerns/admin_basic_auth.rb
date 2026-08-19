# frozen_string_literal: true

# HTTP Basic del panel admin (ADMIN_USERNAME / ADMIN_PASSWORD), extraído como concern para que
# el panel nuevo de órdenes lo use sin modificar Admin::PaymentsController, que mantiene su propia
# copia intacta (el proyecto de inscripción es aditivo).
module AdminBasicAuth
  extend ActiveSupport::Concern

  included do
    before_action :require_admin_access
  end

  private

  def require_admin_access
    if ENV["ADMIN_PASSWORD"].blank?
      raise ActionController::RoutingError, "Not Found" if Rails.env.production?

      return
    end

    authenticate_or_request_with_http_basic("Admin CLEV") do |username, password|
      admin_username = ENV.fetch("ADMIN_USERNAME", "admin")
      admin_password = ENV["ADMIN_PASSWORD"]

      secure_compare_admin(username, admin_username) && secure_compare_admin(password, admin_password)
    end
  end

  def secure_compare_admin(given, expected)
    ActiveSupport::SecurityUtils.secure_compare(given.to_s, expected.to_s)
  rescue ArgumentError
    false
  end
end
