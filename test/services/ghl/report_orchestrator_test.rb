# frozen_string_literal: true

require "test_helper"
require "support/order_factory"

class Ghl::ReportOrchestratorTest < ActiveSupport::TestCase
  include OrderFactory

  # Cliente de mentira: registra las llamadas y permite forzar fallos por paso.
  class FakeGhlClient
    attr_reader :upserts, :tags

    def initialize(falla_upsert: nil, falla_tags: nil, contact_id: "cnt_7Xk2")
      @falla_upsert = falla_upsert
      @falla_tags = falla_tags
      @contact_id = contact_id
      @upserts = []
      @tags = []
    end

    def source = "CLEV inscripción"

    def upsert_contact(attrs)
      @upserts << attrs
      raise Ghl::Client::Error, @falla_upsert if @falla_upsert

      { success: true, status: 200, contact_id: @contact_id, new: true, trace_id: "trace-1", data: {} }
    end

    def add_tags(contact_id:, tags:)
      @tags << { contact_id: contact_id, tags: tags }
      raise Ghl::Client::Error, @falla_tags if @falla_tags

      { success: true, status: 201, tags: tags, data: {} }
    end
  end

  test "reporta el contacto y aplica el tag en dos llamadas" do
    order = crear_orden(status: "paid")
    client = FakeGhlClient.new

    resultado = Ghl::ReportOrchestrator.report_and_record!(order, client: client)
    order.reload

    assert resultado[:reported]
    assert_equal 1, client.upserts.size
    assert_equal 1, client.tags.size
    assert_equal "cnt_7Xk2", order.crm_contact_id
    assert_equal "desarrollo-de-aplicaciones-moviles-2026", order.crm_tag
    assert order.crm_reported?
    assert order.crm_reported_at.present?
    assert_nil order.crm_error
  end

  test "el payload del contacto sale de los campos de facturación, con país en ISO alpha-2" do
    order = crear_orden(status: "paid")
    client = FakeGhlClient.new

    Ghl::ReportOrchestrator.report_and_record!(order, client: client)
    payload = client.upserts.first

    assert_equal "Valentina", payload[:firstName]
    assert_equal "Torres", payload[:lastName]
    assert_equal "valentina.torres@correo.com", payload[:email]
    assert_equal "+593 99 123 4567", payload[:phone]
    assert_equal "Av. Amazonas N34-120", payload[:address1]
    assert_equal "Quito", payload[:city]
    assert_equal "EC", payload[:country]
    assert_equal "CLEV inscripción", payload[:source]
  end

  test "el tag nunca viaja dentro del upsert (sobrescribiría los tags del contacto)" do
    order = crear_orden(status: "paid")
    client = FakeGhlClient.new

    Ghl::ReportOrchestrator.report_and_record!(order, client: client)

    assert_not client.upserts.first.key?(:tags)
    assert_equal [ "desarrollo-de-aplicaciones-moviles-2026" ], client.tags.first[:tags]
  end

  test "un país sin equivalente ISO se envía sin país y no bloquea el reporte" do
    order = crear_orden(status: "paid", country: "Wakanda")
    client = FakeGhlClient.new

    resultado = Ghl::ReportOrchestrator.report_and_record!(order, client: client)

    assert resultado[:reported]
    assert_nil client.upserts.first[:country]
    assert_equal "Wakanda", order.reload.country, "El dato crudo de la orden no se altera"
  end

  test "solo se reportan órdenes pagadas" do
    %w[pending rejected failed].each do |estado|
      order = crear_orden(status: estado)
      client = FakeGhlClient.new

      resultado = Ghl::ReportOrchestrator.report_and_record!(order, client: client)

      assert resultado[:skipped]
      assert_equal "orden_no_pagada", resultado[:reason]
      assert_empty client.upserts
      assert_not order.reload.crm_reported?
    end
  end

  test "una orden ya reportada se omite (idempotencia)" do
    order = crear_orden(status: "paid", crm_reported: true, crm_reported_at: Time.current)
    client = FakeGhlClient.new

    resultado = Ghl::ReportOrchestrator.report_and_record!(order, client: client)

    assert resultado[:skipped]
    assert_equal "already_reported", resultado[:reason]
    assert_empty client.upserts
  end

  test "si el upsert falla no se marca reportado y queda el error registrado" do
    order = crear_orden(status: "paid")
    client = FakeGhlClient.new(falla_upsert: "Timeout tras 25s")

    resultado = Ghl::ReportOrchestrator.report_and_record!(order, client: client)
    order.reload

    assert_not resultado[:reported]
    assert_not order.crm_reported?
    assert_equal "Timeout tras 25s", order.crm_error
    assert_nil order.crm_contact_id
    assert_empty client.tags
  end

  test "si el upsert funciona pero el tag falla, se guarda el contacto para reintentar solo el tag" do
    order = crear_orden(status: "paid")
    client = FakeGhlClient.new(falla_tags: "422 tag inválido")

    resultado = Ghl::ReportOrchestrator.report_and_record!(order, client: client)
    order.reload

    assert_not resultado[:reported]
    assert_not order.crm_reported?
    assert_equal "cnt_7Xk2", order.crm_contact_id
    assert_match(/tag inválido/, order.crm_error)

    # Reintento: con el contacto ya guardado, solo repite el paso del tag.
    reintento = FakeGhlClient.new
    assert Ghl::ReportOrchestrator.retry_report!(order.reference, client: reintento)

    assert_empty reintento.upserts, "El upsert no debe repetirse si ya hay contacto"
    assert_equal 1, reintento.tags.size
    assert order.reload.crm_reported?
  end

  test "si el CRM no devuelve id de contacto, el reporte queda en error" do
    order = crear_orden(status: "paid")
    client = FakeGhlClient.new(contact_id: nil)

    resultado = Ghl::ReportOrchestrator.report_and_record!(order, client: client)

    assert_not resultado[:reported]
    assert_match(/no devolvió el id del contacto/, order.reload.crm_error)
    assert_empty client.tags
  end

  test "retry_report! ignora órdenes inexistentes o ya reportadas" do
    reportada = crear_orden(status: "paid", crm_reported: true)

    assert_not Ghl::ReportOrchestrator.retry_report!("INSC-NO-EXISTE", client: FakeGhlClient.new)
    assert_not Ghl::ReportOrchestrator.retry_report!(reportada.reference, client: FakeGhlClient.new)
  end

  test "reconcile_all_pending! barre solo las órdenes pagadas sin reportar" do
    pendiente_pago = crear_orden
    pagada = crear_orden(status: "paid")
    ya_reportada = crear_orden(status: "paid", crm_reported: true)
    client = FakeGhlClient.new

    resultados = Ghl::ReportOrchestrator.reconcile_all_pending!(client: client)
    referencias = resultados.map { |entry| entry[:reference] }

    assert_includes referencias, pagada.reference
    assert_not_includes referencias, pendiente_pago.reference
    assert_not_includes referencias, ya_reportada.reference
    assert pagada.reload.crm_reported?
  end

  test "una orden sin datos para calcular el tag queda con error y sin reportar" do
    order = crear_orden(status: "paid")
    # El slug es readonly en el modelo: para simular el dato corrupto se escribe por SQL.
    Order.connection.execute("UPDATE orders SET course_slug = '' WHERE id = #{order.id}")
    order.reload
    client = FakeGhlClient.new

    resultado = Ghl::ReportOrchestrator.report_and_record!(order, client: client)

    assert_not resultado[:reported]
    assert_match(/tag curso-año/, order.reload.crm_error)
    assert_empty client.upserts
  end

  test "CrmReportJob delega en el orquestador y tolera referencias inexistentes" do
    order = crear_orden(status: "paid")

    assert_nothing_raised { CrmReportJob.perform_now("INSC-NO-EXISTE") }

    # Con GHL deshabilitado en test, el job registra el error en la orden en vez de reventar.
    assert_nothing_raised { CrmReportJob.perform_now(order.reference) }
    assert_not order.reload.crm_reported?
    assert_match(/deshabilitada/, order.crm_error)
  end
end
