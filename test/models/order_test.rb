# frozen_string_literal: true

require "test_helper"

class OrderTest < ActiveSupport::TestCase
  SNAPSHOT = {
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

  FACTURACION = {
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

  def build_order(snapshot_overrides = {}, facturacion_overrides = {})
    Order.build_from_snapshot(
      SNAPSHOT.merge(snapshot_overrides),
      FACTURACION.merge(facturacion_overrides)
    )
  end

  test "build_from_snapshot arma una orden válida con referencia INSC- y desglose de IVA 0%" do
    order = build_order

    assert order.valid?, order.errors.full_messages.to_sentence
    assert_match(/\AINSC-\d{14}-[A-F0-9]{6}\z/, order.reference)
    assert_equal "pending", order.status
    assert_equal 40.0, order.amount.to_f
    assert_equal 40.0, order.amount_without_tax.to_f
    assert_equal 0.0, order.amount_with_tax.to_f
    assert_equal 0.0, order.tax_value.to_f
    assert_equal 0.0, order.tax_rate.to_f
    assert_equal "desarrollo-de-aplicaciones-moviles", order.course_slug
    assert order.return_token.present?
  end

  test "el desglose de IVA siempre cuadra con el monto (invariante Pagomedios)" do
    [ 10.0, 20.0, 40.55, 99.99 ].each do |monto|
      order = build_order(amount: monto)
      suma = order.amount_with_tax + order.amount_without_tax + order.tax_value

      assert_equal order.amount, suma, "El desglose no cuadra para #{monto}"
    end
  end

  test "una orden con desglose inconsistente no es válida" do
    order = build_order
    order.tax_value = 5.0

    assert_not order.valid?
    assert_match(/no cuadra con el desglose de IVA/, order.errors.full_messages.to_sentence)
  end

  test "el check constraint de BD rechaza un desglose inconsistente aunque se salte el modelo" do
    order = build_order
    order.save!

    # Se va por SQL crudo (dentro de un savepoint) porque el modelo ya bloquea la escritura
    # vía attr_readonly: lo que se prueba acá es la red de seguridad de la base de datos.
    error = assert_raises(ActiveRecord::StatementInvalid) do
      Order.transaction(requires_new: true) do
        Order.connection.execute("UPDATE orders SET tax_value = 5.0 WHERE id = #{order.id}")
      end
    end

    assert_match(/chk_orders_desglose_iva_cuadra/, error.message)
  end

  test "el check constraint de BD rechaza montos no positivos" do
    order = build_order
    order.save!

    error = assert_raises(ActiveRecord::StatementInvalid) do
      Order.transaction(requires_new: true) do
        Order.connection.execute(
          "UPDATE orders SET amount = 0, amount_without_tax = 0 WHERE id = #{order.id}"
        )
      end
    end

    assert_match(/chk_orders_amount_positivo/, error.message)
  end

  test "el monto debe ser mayor a 0" do
    order = build_order(amount: 0)

    assert_not order.valid?
    assert_includes order.errors[:amount], "must be greater than 0"
  end

  test "la referencia es única" do
    order = build_order
    order.save!

    duplicada = build_order
    duplicada.reference = order.reference

    assert_not duplicada.valid?
    assert_includes duplicada.errors[:reference], "has already been taken"
  end

  test "el snapshot de curso y monto es inmutable una vez creada la orden" do
    order = build_order
    order.save!

    assert_raises(ActiveRecord::ReadonlyAttributeError) { order.update!(amount: 99.0) }
    assert_raises(ActiveRecord::ReadonlyAttributeError) { order.update!(course_name: "Otro curso") }
    assert_raises(ActiveRecord::ReadonlyAttributeError) { order.update!(option_code: "RESERVA") }

    assert_equal 40.0, order.reload.amount.to_f
    assert_equal "Desarrollo de aplicaciones móviles", order.course_name
  end

  test "los campos de facturación son obligatorios" do
    %i[first_name last_name identification_type_code identification_number email phone address city country].each do |campo|
      order = build_order({}, campo => nil)

      assert_not order.valid?, "Se esperaba que #{campo} fuera obligatorio"
      assert_includes order.errors[campo], "can't be blank"
    end
  end

  test "el correo debe tener formato válido" do
    order = build_order({}, email: "no-es-un-correo")

    assert_not order.valid?
    assert_includes order.errors[:email], "is invalid"
  end

  test "final? distingue estados finales de pending" do
    order = build_order
    order.save!

    assert_not order.final?
    assert order.pendiente?

    Order::ESTADOS_FINALES.each do |estado|
      order.update_column(:status, estado)
      assert order.reload.final?, "#{estado} debería ser final"
    end
  end

  test "tag_crm usa el año de edición del curso cuando Q10 lo expone" do
    order = build_order(course_edition_year: 2026)

    assert_equal "desarrollo-de-aplicaciones-moviles-2026", order.tag_crm
  end

  test "tag_crm cae al año del pago cuando Q10 no expone el año de edición" do
    order = build_order(course_edition_year: nil)
    order.save!
    order.update_columns(transaction_at: Time.zone.parse("2027-03-04 10:00:00"))

    assert_equal "desarrollo-de-aplicaciones-moviles-2027", order.reload.tag_crm
  end

  test "tag_crm cae al año del intento cuando no hay año de edición ni fecha de pago" do
    order = build_order(course_edition_year: nil)
    order.save!

    assert_equal "desarrollo-de-aplicaciones-moviles-#{order.created_at.year}", order.tag_crm
  end

  test "crm_status deriva el estado del reporte sin columna propia" do
    order = build_order
    order.save!

    assert_equal :no_aplica, order.crm_status

    order.update_column(:status, "paid")
    assert_equal :pendiente, order.reload.crm_status

    order.update!(crm_error: "Timeout tras 25s")
    assert_equal :error, order.crm_status

    order.update!(crm_reported: true, crm_reported_at: Time.current)
    assert_equal :reportado, order.crm_status
  end

  test "crm_pendientes solo incluye órdenes pagadas sin reportar" do
    pendiente = build_order
    pendiente.save!

    pagada_sin_reportar = build_order
    pagada_sin_reportar.save!
    pagada_sin_reportar.update_column(:status, "paid")

    pagada_reportada = build_order
    pagada_reportada.save!
    pagada_reportada.update_columns(status: "paid", crm_reported: true)

    referencias = Order.crm_pendientes.pluck(:reference)

    assert_includes referencias, pagada_sin_reportar.reference
    assert_not_includes referencias, pendiente.reference
    assert_not_includes referencias, pagada_reportada.reference
    assert pagada_sin_reportar.needs_crm_report?
    assert_not pagada_reportada.reload.needs_crm_report?
  end

  test "los scopes de filtro del panel se componen y toleran valores vacíos" do
    ayurveda = build_order(course_code: "AYUR", course_name: "Ayurveda")
    ayurveda.save!
    ayurveda.update_column(:status, "paid")

    otra = build_order
    otra.save!

    resultado = Order.con_estado("paid").del_curso("AYUR").entre(Date.current, Date.current)

    assert_equal [ ayurveda.reference ], resultado.pluck(:reference)
    assert_equal Order.count, Order.con_estado(nil).del_curso("").entre(nil, nil).count
  end

  test "PAGOMEDIOS_STATUS_MAP traduce los códigos crudos de la pasarela a estados de negocio" do
    assert_equal "paid", Order::PAGOMEDIOS_STATUS_MAP["1"]
    assert_equal "rejected", Order::PAGOMEDIOS_STATUS_MAP["2"]
    assert_equal "rejected", Order::PAGOMEDIOS_STATUS_MAP["3"]
    assert_nil Order::PAGOMEDIOS_STATUS_MAP["99"]
  end
end
