# frozen_string_literal: true

require "test_helper"

class Q10::CuotaReminderNotifierTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @previous_days = ENV["CUOTA_REMINDER_DAYS"]
    ENV["CUOTA_REMINDER_DAYS"] = "5"

    Payment.create!(
      reference: "CLEV-REMINDER-CANDIDATE",
      status: "pending",
      amount: 20,
      currency: "USD",
      numero_identificacion: "1102369319",
      codigo_persona: "119832177599"
    )
  end

  teardown do
    if @previous_days.nil?
      ENV.delete("CUOTA_REMINDER_DAYS")
    else
      ENV["CUOTA_REMINDER_DAYS"] = @previous_days
    end
  end

  test "reminder_days_before usa el valor configurado o el default" do
    ENV["CUOTA_REMINDER_DAYS"] = "5"
    assert_equal 5, Q10::CuotaReminderNotifier.reminder_days_before

    ENV["CUOTA_REMINDER_DAYS"] = "0"
    assert_equal Q10::CuotaReminderNotifier::DEFAULT_DAYS, Q10::CuotaReminderNotifier.reminder_days_before
  end

  test "envía recordatorio cuando faltan exactamente N días" do
    due_date = 5.days.from_now.to_date
    client = stub_client(
      estudiante: {
        "Email" => "estudiante@example.com",
        "Primer_nombre" => "Ana",
        "Primer_apellido" => "Pérez",
        "Codigo_persona" => "119832177599"
      },
      creditos: [
        {
          "Consecutivo_credito" => 675,
          "Nombre_programa" => "Programa demo",
          "Nombre_periodo" => "2026",
          "Cuotas" => [
            {
              "Numero_cuota" => 9,
              "Fecha_cuota" => due_date.iso8601,
              "Pendiente" => 20.0,
              "Pagado" => 0
            }
          ]
        }
      ]
    )

    assert_emails 1 do
      summary = Q10::CuotaReminderNotifier.new(client: client, periods: stub_periods).call
      assert_equal 1, summary[:sent]
    end

    assert CuotaReminderDelivery.exists?(
      numero_identificacion: "1102369319",
      numero_cuota: "9",
      days_before: 5
    )
  end

  test "envía aviso único cuando la cuota ya está vencida" do
    due_date = 2.days.ago.to_date
    client = stub_client(
      estudiante: {
        "Email" => "estudiante@example.com",
        "Codigo_persona" => "119832177599"
      },
      creditos: [
        {
          "Consecutivo_credito" => 675,
          "Cuotas" => [
            {
              "Numero_cuota" => 8,
              "Fecha_cuota" => due_date.iso8601,
              "Pendiente" => 25.0
            }
          ]
        }
      ]
    )

    notifier = Q10::CuotaReminderNotifier.new(client: client, periods: stub_periods)
    assert_emails 1 do
      summary = notifier.call
      assert_equal 1, summary[:sent]
    end

    assert CuotaReminderDelivery.exists?(
      numero_identificacion: "1102369319",
      numero_cuota: "8",
      days_before: Q10::CuotaReminderNotifier::OVERDUE_MARKER
    )

    assert_emails 0 do
      summary = notifier.call
      assert_equal 0, summary[:sent]
    end
  end

  test "no reenvía el mismo recordatorio preventivo" do
    due_date = 5.days.from_now.to_date
    client = stub_client(
      estudiante: {
        "Email" => "estudiante@example.com",
        "Codigo_persona" => "119832177599"
      },
      creditos: [
        {
          "Consecutivo_credito" => 675,
          "Cuotas" => [
            {
              "Numero_cuota" => 9,
              "Fecha_cuota" => due_date.iso8601,
              "Pendiente" => 20.0
            }
          ]
        }
      ]
    )

    notifier = Q10::CuotaReminderNotifier.new(client: client, periods: stub_periods)
    assert_emails 1 do
      notifier.call
    end
    assert_emails 0 do
      summary = notifier.call
      assert_equal 0, summary[:sent]
      assert_operator summary[:skipped], :>=, 1
    end
  end

  private

  def stub_periods
    Object.new.tap do |periods|
      periods.define_singleton_method(:default_consecutivo) { "12" }
    end
  end

  def stub_client(estudiante:, creditos:)
    Object.new.tap do |client|
      client.define_singleton_method(:enabled?) { true }
      client.define_singleton_method(:fetch_estudiante) { |_| { data: estudiante } }
      client.define_singleton_method(:fetch_creditos) { |_| { data: creditos } }
      client.define_singleton_method(:fetch_ordenes_pago) { |_| { data: [] } }
    end
  end
end
