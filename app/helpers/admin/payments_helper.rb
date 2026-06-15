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

    def payment_q10_label(reported)
      reported ? "Sí" : "No"
    end
  end
end
