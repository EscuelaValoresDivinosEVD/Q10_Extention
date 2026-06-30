# frozen_string_literal: true

class Payment < ApplicationRecord
  STATUSES = %w[pending authorized rejected reversed failed].freeze

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

  scope :authorized, -> { where(status: "authorized") }
  scope :q10_reported, -> { where(q10_reported: true) }
  scope :q10_pending_report, -> { authorized.where(q10_reported: false) }

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
