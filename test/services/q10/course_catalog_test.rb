# frozen_string_literal: true

require "test_helper"

class Q10::CourseCatalogTest < ActiveSupport::TestCase
  CURSO_ABIERTO = {
    "Codigo" => "EJO1",
    "Nombre" => "Desarrollo de aplicaciones móviles",
    "Cupo_maximo" => 10,
    "Cantidad_estudiantes_matriculados" => 3,
    "Fecha_inicio" => "2026-01-01T12:00:00Z",
    "Fecha_fin" => "2026-06-30T12:00:00Z",
    "Estado" => "Abierto",
    "Aplica_matricula_en_linea" => true,
    "Nombre_docente" => "Gilberto Lopera",
    "Nombre_descuento" => "Descuento nuevos"
  }.freeze

  CURSO_SIN_CUPOS = CURSO_ABIERTO.merge(
    "Codigo" => "LLENO", "Cantidad_estudiantes_matriculados" => 10
  ).freeze

  CURSO_CERRADO = CURSO_ABIERTO.merge("Codigo" => "CERRADO", "Estado" => "Cerrado").freeze

  CURSO_SIN_MATRICULA_LINEA = CURSO_ABIERTO.merge(
    "Codigo" => "SINLINEA", "Aplica_matricula_en_linea" => false
  ).freeze

  setup do
    Rails.cache.clear
  end

  def client_con(cursos, enabled: true)
    client = Q10::ApiClient.new(config: Rails.application.config_for(:q10).deep_symbolize_keys.merge(enabled: enabled))
    client.define_singleton_method(:fetch_cursos_disponibles) { |**| { success: true, data: cursos } }
    client
  end

  def client_que_falla(enabled: true)
    client = Q10::ApiClient.new(config: Rails.application.config_for(:q10).deep_symbolize_keys.merge(enabled: enabled))
    client.define_singleton_method(:fetch_cursos_disponibles) do |**|
      raise Q10::ApiClient::Error, "No fue posible conectar con Q10"
    end
    client
  end

  test "all normaliza el contrato real de Q10 al formato de la UI" do
    catalogo = Q10::CourseCatalog.new(client: client_con([ CURSO_ABIERTO ]))
    curso = catalogo.all.first

    assert_equal "EJO1", curso[:code]
    assert_equal "Desarrollo de aplicaciones móviles", curso[:name]
    assert_equal "Abierto", curso[:estado]
    assert_equal true, curso[:aplica_matricula_en_linea]
    assert_equal 10, curso[:cupo_maximo]
    assert_equal 3, curso[:matriculados]
    assert_equal 2026, curso[:edition_year]
    assert_not catalogo.error?
  end

  test "all no mapea datos académicos ni de descuento (fuera de alcance del checkout)" do
    catalogo = Q10::CourseCatalog.new(client: client_con([ CURSO_ABIERTO ]))
    curso = catalogo.all.first

    assert_not curso.key?(:nombre_docente)
    assert_not curso.key?(:descuento)
    assert_equal %i[code name estado aplica_matricula_en_linea cupo_maximo matriculados
                    edition_year fecha_inicio fecha_fin].sort, curso.keys.sort
  end

  test "all sirve la caché cuando Q10 deja de responder dentro del TTL" do
    catalogo_ok = Q10::CourseCatalog.new(client: client_con([ CURSO_ABIERTO ]))
    assert_equal 1, catalogo_ok.all.size

    catalogo_caido = Q10::CourseCatalog.new(client: client_que_falla)

    assert_equal 1, catalogo_caido.all.size
    assert_not catalogo_caido.error?, "Con caché vigente el usuario no debe ver el estado de error"
  end

  test "all devuelve estado de error (no datos inventados) si Q10 falla y no hay caché" do
    catalogo = Q10::CourseCatalog.new(client: client_que_falla)

    assert_equal [], catalogo.all
    assert catalogo.error?
    assert_match(/No fue posible conectar con Q10/, catalogo.error_message)
  end

  test "all devuelve vacío si la integración Q10 está deshabilitada" do
    catalogo = Q10::CourseCatalog.new(client: client_con([ CURSO_ABIERTO ], enabled: false))

    assert_equal [], catalogo.all
    assert catalogo.deshabilitado?
    assert_not catalogo.error?
  end

  test "find_by_code ubica el curso por el Codigo de Q10" do
    catalogo = Q10::CourseCatalog.new(client: client_con([ CURSO_ABIERTO, CURSO_CERRADO ]))

    assert_equal "Desarrollo de aplicaciones móviles", catalogo.find_by_code("EJO1")[:name]
    assert_nil catalogo.find_by_code("NO-EXISTE")
    assert_nil catalogo.find_by_code(nil)
  end

  test "disponible? exige curso abierto, con matrícula en línea y con cupos" do
    cursos = [ CURSO_ABIERTO, CURSO_SIN_CUPOS, CURSO_CERRADO, CURSO_SIN_MATRICULA_LINEA ]
    catalogo = Q10::CourseCatalog.new(client: client_con(cursos))

    assert catalogo.disponible?(catalogo.find_by_code("EJO1"))
    assert_not catalogo.disponible?(catalogo.find_by_code("LLENO"))
    assert_not catalogo.disponible?(catalogo.find_by_code("CERRADO"))
    assert_not catalogo.disponible?(catalogo.find_by_code("SINLINEA"))
  end

  test "visible? separa 'existe pero sin cupos' de 'no accesible'" do
    cursos = [ CURSO_SIN_CUPOS, CURSO_CERRADO, CURSO_SIN_MATRICULA_LINEA ]
    catalogo = Q10::CourseCatalog.new(client: client_con(cursos))

    # Sin cupos: sigue siendo visible (se muestra "sin cupos disponibles"), no 404.
    assert catalogo.visible?(catalogo.find_by_code("LLENO"))
    assert_not catalogo.cupos?(catalogo.find_by_code("LLENO"))

    # Cerrado o sin matrícula en línea: ni siquiera es accesible.
    assert_not catalogo.visible?(catalogo.find_by_code("CERRADO"))
    assert_not catalogo.visible?(catalogo.find_by_code("SINLINEA"))
  end

  test "cupos_disponibles resta matriculados y nunca es negativo" do
    catalogo = Q10::CourseCatalog.new(client: client_con([ CURSO_ABIERTO, CURSO_SIN_CUPOS ]))

    assert_equal 7, catalogo.cupos_disponibles(catalogo.find_by_code("EJO1"))
    assert_equal 0, catalogo.cupos_disponibles(catalogo.find_by_code("LLENO"))
  end

  test "option_snapshot revalida disponibilidad y no inventa un precio" do
    catalogo = Q10::CourseCatalog.new(client: client_con([ CURSO_ABIERTO ]))
    snapshot = catalogo.option_snapshot(course_code: "EJO1")

    assert_equal "EJO1", snapshot[:course_code]
    assert_equal "Desarrollo de aplicaciones móviles", snapshot[:course_name]
    assert_equal 2026, snapshot[:course_edition_year]
    assert_equal 0.0, snapshot[:tax_rate]
    assert_not snapshot.key?(:amount), "Q10 no expone precio: el snapshot no debe traer monto"
    assert_not snapshot.key?(:option_code)
  end

  test "option_snapshot devuelve nil si el curso dejó de estar disponible" do
    cursos = [ CURSO_SIN_CUPOS, CURSO_CERRADO ]
    catalogo = Q10::CourseCatalog.new(client: client_con(cursos))

    assert_nil catalogo.option_snapshot(course_code: "LLENO")
    assert_nil catalogo.option_snapshot(course_code: "CERRADO")
    assert_nil catalogo.option_snapshot(course_code: "NO-EXISTE")
  end
end
