# frozen_string_literal: true

require "caxlsx"

module Admin
  class PaymentsExcelExporter
    include Admin::PaymentsHelper

    HEADERS = [
      "ID",
      "Referencia",
      "Estado",
      "Monto",
      "Moneda",
      "Identificación",
      "Nombre",
      "Apellido",
      "Código persona",
      "Cuotas",
      "Crédito",
      "Q10",
      "Creado",
      "Autorizado",
      "Código autorización",
      "Mensaje Pagomedios",
      "Error Q10"
    ].freeze

    def initialize(payments)
      @payments = payments
    end

    def filename
      stamp = Time.zone.now.strftime("%Y%m%d_%H%M")
      "pagos_clev_#{stamp}.xlsx"
    end

    def to_stream
      package = Axlsx::Package.new
      workbook = package.workbook

      workbook.add_worksheet(name: "Pagos") do |sheet|
        sheet.add_row HEADERS
        @payments.each do |payment|
          sheet.add_row(row_for(payment), types: row_types)
        end
      end

      package.to_stream.read
    end

    private

    def row_for(payment)
      [
        payment.id,
        payment.reference,
        payment_status_label(payment.status),
        payment.amount.to_f,
        payment.currency,
        payment.numero_identificacion.to_s,
        payment.nombre.to_s,
        payment.apellido.to_s,
        payment.codigo_persona.to_s,
        payment_cuotas_label(payment.cuotas),
        payment.consecutivo_credito.to_s,
        payment_q10_label(payment),
        format_datetime(payment.created_at),
        format_datetime(payment.transaction_at),
        payment.authorization_code.to_s,
        payment.pagomedios_message.to_s,
        payment.q10_error.to_s
      ]
    end

    def row_types
      [
        :integer, :string, :string, :float, :string,
        :string, :string, :string, :string, :string,
        :string, :string, :string, :string, :string,
        :string, :string
      ]
    end

    def format_datetime(value)
      return "" if value.blank?

      I18n.l(value, format: :short)
    end
  end
end
