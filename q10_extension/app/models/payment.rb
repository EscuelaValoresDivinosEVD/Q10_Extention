# frozen_string_literal: true

class Payment < ApplicationRecord
  STATUSES = %w[pending authorized rejected reversed failed].freeze

  validates :reference, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :amount, numericality: { greater_than: 0 }
  validates :currency, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :successful, -> { where(status: "authorized") }
  scope :failed_attempts, -> { where(status: %w[rejected reversed failed]) }

  def successful?
    status == "authorized"
  end

  def pending?
    status == "pending"
  end
end
