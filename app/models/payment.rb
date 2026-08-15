# frozen_string_literal: true

class Payment < ApplicationRecord
  STATUSES = %w[pending authorized rejected failed cancelled].freeze
  DEFAULT_STALE_PENDING_DAYS = 7

  validates :reference, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :amount, numericality: { greater_than: 0 }
  validates :currency, presence: true

  def successful?
    status == "authorized"
  end

  def pending?
    status == "pending"
  end

  def cancelled?
    status == "cancelled"
  end

  def nombre_completo
    [ nombre, apellido ].map(&:presence).compact.join(" ").presence
  end

  scope :authorized, -> { where(status: "authorized") }
  scope :pending, -> { where(status: "pending") }
  scope :stale_pending, -> { pending.where(created_at: ..stale_pending_after.ago) }
  scope :q10_reported, -> { where(q10_reported: true) }
  scope :q10_pending_report, -> { authorized.where(q10_reported: false) }
  scope :created_from, ->(date) { date.present? ? where(created_at: date.in_time_zone.beginning_of_day..) : all }
  scope :created_to, ->(date) { date.present? ? where(created_at: ..date.in_time_zone.end_of_day) : all }
  scope :created_between, ->(from_date, to_date) { created_from(from_date).created_to(to_date) }

  def self.stale_pending_days
    days = ENV.fetch("PAYMENT_STALE_PENDING_DAYS", DEFAULT_STALE_PENDING_DAYS.to_s).to_i
    days.positive? ? days : DEFAULT_STALE_PENDING_DAYS
  end

  def self.stale_pending_after
    stale_pending_days.days
  end

  def self.cancel_stale_pending!
    cancelled_ids = []

    stale_pending.find_each do |payment|
      payment.update!(status: "cancelled")
      cancelled_ids << payment.id
    end

    cancelled_ids
  end

  def needs_q10_report?
    successful? && !q10_reported
  end

  def credit_context?
    consecutivo_credito.present? && codigo_persona.present?
  end

  def report_context
    {
      reference: reference,
      codigo_persona: codigo_persona,
      codigo_cajero: codigo_cajero,
      consecutivo_credito: consecutivo_credito,
      amount: amount.to_f,
      cuotas: Array(cuotas),
      webhook_payload: pagomedios_payload
    }
  end
end
