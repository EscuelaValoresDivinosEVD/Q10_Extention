# frozen_string_literal: true

class CuotaRemindersJob < ApplicationJob
  queue_as :default

  def perform
    summary = Q10::CuotaReminderNotifier.new.call

    Rails.logger.info(
      "[CuotaReminder] Job: enviados=#{summary[:sent]} " \
      "omitidos=#{summary[:skipped]} errores=#{summary[:errors]} " \
      "días_antes=#{Q10::CuotaReminderNotifier.reminder_days_before}"
    )

    summary
  end
end
