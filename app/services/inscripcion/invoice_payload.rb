# frozen_string_literal: true

module Inscripcion
  # Datos de facturación que viajan a Pagomedios cuando se pide `generate_invoice: 1`.
  #
  # 🚧 TODO (pendiente #2 del kickoff): confirmar el SHAPE EXACTO de estos campos contra la doc de
  # "Links de pago" de Pagomedios o probando en sandbox. Lo que SÍ está confirmado es el SET de
  # datos que exige el SRI (2026-07-20): nombre, apellido, tipo y número de identificación, correo,
  # teléfono, dirección, ciudad y país. Lo que falta es cómo se llaman esas claves en el body de la
  # API v2 — los nombres de abajo son la mejor aproximación (snake_case, consistente con el resto
  # del body que ya funciona), no un contrato verificado.
  #
  # El armado vive acá, aislado, para que cerrar ese pendiente sea cambiar UN archivo.
  class InvoicePayload
    def self.for(order)
      new(order).to_h
    end

    def initialize(order)
      @order = order
    end

    def to_h
      {
        # TODO: confirmar nombres exactos contra la doc/sandbox de Pagomedios v2.
        document: @order.identification_number,
        document_type: @order.identification_type_code,
        name: @order.first_name,
        last_name: @order.last_name,
        email: @order.email,
        phone: @order.phone,
        address: @order.address,
        city: @order.city,
        country: @order.country
      }
    end
  end
end
