# frozen_string_literal: true

require "test_helper"

class AccessRateLimiterTest < ActiveSupport::TestCase
  setup do
    @store = ActiveSupport::Cache::MemoryStore.new
    @limiter = AccessRateLimiter.new(store: @store)
    @request = ActionDispatch::TestRequest.create("REMOTE_ADDR" => "203.0.113.10")
  end

  test "permite hasta 15 solicitudes en la ventana" do
    15.times do
      assert_equal :allowed, @limiter.check!(@request, email: "alumno@correo.com")
    end
  end

  test "bloquea la solicitud 16 desde la misma IP" do
    15.times { @limiter.check!(@request) }

    assert_equal :blocked, @limiter.check!(@request)
  end

  test "bloquea la solicitud 16 con el mismo correo aunque cambie la IP" do
    15.times do
      req = ActionDispatch::TestRequest.create("REMOTE_ADDR" => "203.0.113.#{rand(1..200)}")
      assert_equal :allowed, @limiter.check!(req, email: "alumno@correo.com")
    end

    other_ip_request = ActionDispatch::TestRequest.create("REMOTE_ADDR" => "198.51.100.1")
    assert_equal :blocked, @limiter.check!(other_ip_request, email: "alumno@correo.com")
  end

  test "mantiene el bloqueo durante una hora" do
    travel_to Time.zone.parse("2026-06-27 10:00:00") do
      16.times { @limiter.check!(@request) }
      assert_equal :blocked, @limiter.check!(@request)
    end

    travel_to Time.zone.parse("2026-06-27 10:59:00") do
      assert_equal :blocked, @limiter.check!(@request)
    end

    travel_to Time.zone.parse("2026-06-27 11:01:00") do
      assert_equal :allowed, @limiter.check!(@request)
    end
  end

  test "reinicia el contador tras la ventana de 5 minutos sin bloqueo" do
    travel_to Time.zone.parse("2026-06-27 10:00:00") do
      10.times { @limiter.check!(@request) }
    end

    travel_to Time.zone.parse("2026-06-27 10:06:00") do
      15.times do
        assert_equal :allowed, @limiter.check!(@request)
      end
    end
  end
end
