# frozen_string_literal: true

require "test_helper"

class CuotaReminderDeliveryTest < ActiveSupport::TestCase
  test "valida campos obligatorios" do
    delivery = CuotaReminderDelivery.new
    assert_not delivery.valid?
    assert_includes delivery.errors[:numero_identificacion], "can't be blank"
  end
end
