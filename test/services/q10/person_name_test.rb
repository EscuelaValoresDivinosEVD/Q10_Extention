# frozen_string_literal: true

require "test_helper"

class Q10::PersonNameTest < ActiveSupport::TestCase
  test "extrae primer nombre y apellido del estudiante Q10" do
    result = Q10::PersonName.from_hash(
      "Primer_nombre" => "Carlos",
      "Segundo_nombre" => "Andrés",
      "Primer_apellido" => "Bedoya",
      "Segundo_apellido" => "Correa"
    )

    assert_equal "Carlos Andrés", result[:nombre]
    assert_equal "Bedoya Correa", result[:apellido]
  end

  test "usa Nombre_completo cuando no hay partes separadas" do
    result = Q10::PersonName.from_hash("Nombre_completo" => "Carlos Bedoya")

    assert_equal "Carlos Bedoya", result[:nombre]
    assert_nil result[:apellido]
  end
end
