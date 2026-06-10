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
end
