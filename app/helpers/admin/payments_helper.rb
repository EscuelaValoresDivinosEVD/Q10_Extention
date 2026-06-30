# frozen_string_literal: true

module Admin
  module PaymentsHelper
    def payment_status_label(status)
      {
        "authorized" => "Autorizado",
        "pending" => "Pendiente",
        "rejected" => "Rechazado",
        "reversed" => "Reversado",
        "failed" => "Fallido"
      }.fetch(status.to_s, status.to_s.humanize)
    end

    def payment_status_class(status)
      "status-pill status-pill--#{status.to_s.tr('_', '-')}"
    end

    def payment_cuotas_label(cuotas)
      Array(cuotas).presence&.join(", ") || "—"
    end

    def payment_q10_label(payment)
      return "Reportado" if payment.q10_reported
      return "—" unless payment.successful?

      payment.q10_error.present? ? "No reportado" : "Pendiente de reporte"
    end

    def payment_q10_status_class(payment)
      return "status-pill status-pill--authorized" if payment.q10_reported
      return "status-pill status-pill--failed" if payment.successful? && payment.q10_error.present?

      "status-pill status-pill--pending"
    end
  end
end
