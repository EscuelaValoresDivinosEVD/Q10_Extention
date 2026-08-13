# frozen_string_literal: true

class CuotaReminderDelivery < ApplicationRecord
  validates :numero_identificacion, :numero_cuota, :fecha_cuota, :days_before, :email, :sent_at, presence: true
  validates :days_before, numericality: { only_integer: true }
end
