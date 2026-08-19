# frozen_string_literal: true

# Filtros del panel de órdenes de inscripción (estado, curso, rango de fechas, estado CRM).
#
# Vive fuera del controller para que el listado y el export CSV usen EXACTAMENTE el mismo scope
# (regla 1 de reporte-ordenes: el CSV respeta los filtros aplicados).
class OrderFilter
  CRM_ESTADOS = %w[reportado pendiente error].freeze

  attr_reader :estado, :curso, :desde_raw, :hasta_raw, :crm, :errores

  def initialize(params = {})
    @estado = params[:estado].to_s.presence
    @curso = params[:curso].to_s.presence
    @crm = params[:crm].to_s.presence
    @desde_raw = params[:desde].to_s.presence
    @hasta_raw = params[:hasta].to_s.presence
    @errores = []

    @desde = parse_fecha(@desde_raw, :desde)
    @hasta = parse_fecha(@hasta_raw, :hasta)

    validar!
  end

  attr_reader :desde, :hasta

  def valido? = errores.empty?

  def aplicado?
    [ estado, curso, crm, desde_raw, hasta_raw ].any?(&:present?)
  end

  # Si los filtros son inválidos se ignoran (se muestra el listado completo + el error), en vez de
  # devolver un resultado silenciosamente incorrecto.
  def scope(base = Order.all)
    return base.recientes unless valido?

    base
      .con_estado(estado_valido)
      .del_curso(curso)
      .entre(desde, hasta)
      .then { |relacion| aplicar_crm(relacion) }
      .recientes
  end

  # Contadores del panel: se calculan sobre el mismo recorte (curso, fechas, CRM) pero SIN el
  # filtro de estado, para que al filtrar "completadas" el resumen siga mostrando cuántas
  # pendientes/rechazadas hay en ese mismo recorte.
  def scope_para_resumen(base = Order.all)
    return base unless valido?

    base.del_curso(curso).entre(desde, hasta).then { |relacion| aplicar_crm(relacion) }
  end

  # Nombre del archivo CSV, con los filtros aplicados: ordenes-completadas-ayurveda-20260813.csv
  def nombre_archivo
    partes = [ "ordenes" ]
    partes << estado_valido if estado_valido.present?
    partes << curso.parameterize if curso.present?
    partes << "crm-#{crm}" if crm_valido.present?
    partes << Time.current.strftime("%Y%m%d-%H%M")

    "#{partes.join('-')}.csv"
  end

  private

  def estado_valido
    estado if Order::STATUSES.include?(estado)
  end

  def crm_valido
    crm if CRM_ESTADOS.include?(crm)
  end

  def aplicar_crm(relacion)
    case crm_valido
    when "reportado" then relacion.crm_reportadas
    when "pendiente" then relacion.crm_sin_reportar
    when "error" then relacion.crm_con_error
    else relacion
    end
  end

  def validar!
    if desde.present? && hasta.present? && desde > hasta
      errores << "La fecha inicial debe ser anterior a la final."
    end

    if estado.present? && estado_valido.blank?
      errores << "El estado seleccionado no es válido."
    end
  end

  def parse_fecha(valor, campo)
    return nil if valor.blank?

    Date.parse(valor)
  rescue Date::Error, TypeError
    errores << "La fecha #{campo == :desde ? 'inicial' : 'final'} no tiene un formato válido."
    nil
  end
end
