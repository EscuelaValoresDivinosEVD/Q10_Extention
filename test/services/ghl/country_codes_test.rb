# frozen_string_literal: true

require "test_helper"

class Ghl::CountryCodesTest < ActiveSupport::TestCase
  test "mapea el país del formulario a ISO alpha-2" do
    assert_equal "EC", Ghl::CountryCodes.alpha2("Ecuador")
    assert_equal "EC", Ghl::CountryCodes.alpha2("  ecuador ")
    assert_equal "ES", Ghl::CountryCodes.alpha2("España")
    assert_equal "CO", Ghl::CountryCodes.alpha2("Colombia")
    assert_equal "US", Ghl::CountryCodes.alpha2("Estados Unidos")
  end

  test "acepta un valor que ya viene en alpha-2" do
    assert_equal "EC", Ghl::CountryCodes.alpha2("EC")
    assert_equal "MX", Ghl::CountryCodes.alpha2("mx")
  end

  test "devuelve nil cuando no puede resolver el país (no bloquea el reporte)" do
    assert_nil Ghl::CountryCodes.alpha2("Wakanda")
    assert_nil Ghl::CountryCodes.alpha2("")
    assert_nil Ghl::CountryCodes.alpha2(nil)
  end
end
