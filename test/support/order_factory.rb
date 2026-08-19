# frozen_string_literal: true

# Constructor de órdenes de inscripción para los tests del funnel.
# Se usa con `include OrderFactory` en el TestCase.
module OrderFactory
  SNAPSHOT_BASE = {
    course_code: "EJO1",
    course_name: "Desarrollo de aplicaciones móviles",
    course_edition_year: 2026,
    option_code: "COMPLETO",
    option_kind: "completo",
    option_label: "Pago completo",
    amount: 40.0,
    currency: "USD",
    tax_rate: 0.0
  }.freeze

  FACTURACION_BASE = {
    first_name: "Valentina",
    last_name: "Torres",
    identification_type_code: "EC01",
    identification_number: "0102030405",
    email: "valentina.torres@correo.com",
    phone: "+593 99 123 4567",
    address: "Av. Amazonas N34-120",
    city: "Quito",
    country: "Ecuador"
  }.freeze

  def build_orden(snapshot: {}, facturacion: {})
    Order.build_from_snapshot(
      SNAPSHOT_BASE.merge(snapshot),
      FACTURACION_BASE.merge(facturacion)
    )
  end

  def crear_orden(snapshot: {}, facturacion: {}, **atributos)
    order = build_orden(snapshot: snapshot, facturacion: facturacion)
    order.save!
    order.update_columns(atributos) if atributos.present?
    order.reload
  end
end
