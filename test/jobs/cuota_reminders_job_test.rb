# frozen_string_literal: true

require "test_helper"

class CuotaRemindersJobTest < ActiveJob::TestCase
  test "ejecuta el notificador" do
    called = false
    stub = Object.new
    stub.define_singleton_method(:call) do
      called = true
      { sent: 0, skipped: 0, errors: 0 }
    end

    original = Q10::CuotaReminderNotifier.method(:new)
    Q10::CuotaReminderNotifier.define_singleton_method(:new) { |**_| stub }

    CuotaRemindersJob.perform_now
    assert called
  ensure
    Q10::CuotaReminderNotifier.define_singleton_method(:new, original)
  end
end
