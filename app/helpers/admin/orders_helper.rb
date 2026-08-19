# frozen_string_literal: true

module Admin
  module OrdersHelper
    # Vocabulario de negocio del panel (ADR-005): la orden habla de "Completada", no de
    # "Autorizado" como el panel de pagos de deudas.
    def order_status_label(status)
      {
        "paid" => "Completada",
        "pending" => "Pendiente",
        "rejected" => "Rechazada",
        "failed" => "Fallida"
      }.fetch(status.to_s, status.to_s.humanize)
    end

    def order_status_class(status)
      "status-pill status-pill--#{status.to_s.tr('_', '-')}"
    end

    def order_crm_label(order)
      {
        reportado: "Reportado",
        pendiente: "Pendiente",
        error: "Error",
        no_aplica: "—"
      }.fetch(order.crm_status, "—")
    end

    def order_crm_class(order)
      case order.crm_status
      when :reportado then "status-pill status-pill--paid"
      when :error then "status-pill status-pill--failed"
      when :pendiente then "status-pill status-pill--pending"
      else "status-pill status-pill--neutral"
      end
    end

    def order_amount(order)
      "#{number_to_currency(order.amount, unit: '$', precision: 2)} #{order.currency}"
    end

    def order_date(fecha, format: :short)
      fecha.present? ? l(fecha, format: format) : "—"
    end

    # El enlace de la pasarela se renderiza como href solo si es https. Evita que un valor
    # inesperado guardado en la orden termine como `javascript:` en el panel (el panel de pagos
    # de deudas no filtra esto — acá no se hereda esa laxitud).
    def order_payment_link(order)
      url = order.payment_url.to_s
      url if url.start_with?("https://")
    end
  end
end
