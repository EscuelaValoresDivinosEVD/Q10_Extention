# frozen_string_literal: true

class Q10DebtsController < ApplicationController
  after_action :prevent_sensitive_page_cache, only: :show

  def show
    payload = ::Q10::LinkToken.verify(params[:token])
    @numero_identificacion = payload["numero_identificacion"] || payload["codigo_persona"]
    @codigo_persona = payload["codigo_persona"].presence || resolve_codigo_persona(@numero_identificacion)
    @student_email = payload.fetch("email")
    @nombre = payload["nombre"].presence
    @apellido = payload["apellido"].presence
    @periods = ::Q10::Periods.new
    @period_options = @periods.options_for_select
    @consecutivo_periodo = @periods.resolve(
      params[:consecutivo_periodo].presence || payload["consecutivo_periodo"]
    )
    @selected_period = @periods.find(@consecutivo_periodo)
    flash.now[:alert] = params[:payment_error] if params[:payment_error].present?
    reconcile_student_pending_q10_reports!
    if params[:payment_success] == "1"
      q10_pending = student_has_pending_q10_reports?
      flash.now[:notice] = if q10_pending
        "Tu pago fue aprobado. Estamos registrando el abono en Q10; los saldos pueden tardar unos segundos en actualizarse."
      else
        "Tu pago fue registrado correctamente. Los saldos se actualizaron."
      end
    elsif student_has_pending_q10_reports?
      flash.now[:notice] = "Tienes pagos aprobados en proceso de registro en Q10. Las cuotas afectadas permanecerán bloqueadas hasta completar el reporte."
    end

    result = ::Q10::ApiClient.new.fetch_creditos(
      numero_identificacion: @numero_identificacion,
      codigo_persona: @codigo_persona,
      consecutivo_periodo: @consecutivo_periodo
    )
    @q10_payload = result[:data]
    @credits_list = extract_credits(@q10_payload)
    @product_names_by_orden = load_product_names_by_orden
    @program_tabs = build_program_tabs(@credits_list)
    @active_consecutivo = active_consecutivo_credito(@program_tabs)
    @student = build_student_summary(@credits_list.first || {})
    @blocked_cuotas_by_credit = PaymentCuotaLock.blocked_cuotas_by_credit(numero_identificacion: @numero_identificacion)

    if @program_tabs.empty?
      flash.now[:alert] = "No encontramos créditos activos en Q10 para el periodo seleccionado."
    end
  rescue ::Q10::LinkToken::Error => e
    redirect_to root_path, alert: e.message
  rescue ::Q10::ApiClient::Error => e
    flash.now[:alert] = "No fue posible consultar los datos en Q10. #{e.message}"
    @q10_payload = {}
    @credits_list = []
    @program_tabs = []
    @product_names_by_orden = {}
    @periods ||= ::Q10::Periods.new
    @period_options ||= @periods.options_for_select
    @consecutivo_periodo ||= @periods.default_consecutivo
    @selected_period ||= @periods.find(@consecutivo_periodo)
    @active_consecutivo = nil
    @student = build_student_summary({})
    render :show, status: :unprocessable_entity
  end

  private

  def prevent_sensitive_page_cache
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, private"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
  end

  def load_product_names_by_orden
    ::Q10::CourseNameResolver.new.product_names_by_orden(codigo_persona: @codigo_persona)
  end

  def resolve_codigo_persona(numero_identificacion)
    return if numero_identificacion.blank?

    estudiante = ::Q10::ApiClient.new.fetch_estudiante(numero_identificacion: numero_identificacion)[:data]
    return unless estudiante.is_a?(Hash)

    estudiante["Codigo_persona"].presence || estudiante["Codigo_estudiante"].presence
  rescue ::Q10::ApiClient::Error => e
    Rails.logger.warn("[Q10] No se pudo resolver Codigo_persona para #{numero_identificacion}: #{e.message}")
    nil
  end

  def reconcile_student_pending_q10_reports!
    return unless ::Q10::ApiClient.new.enabled?

    ::Q10::ReportOrchestrator.reconcile_for_student!(numero_identificacion: @numero_identificacion)
  end

  def student_has_pending_q10_reports?
    Payment.q10_pending_report.exists?(numero_identificacion: @numero_identificacion.to_s.strip)
  end

  def extract_credits(payload)
    case payload
    when Array
      payload.select { |item| item.is_a?(Hash) && item.present? }
    when Hash
      payload.present? ? [ payload ] : []
    else
      []
    end
  end

  def build_program_tabs(credits)
    resolver = ::Q10::CourseNameResolver.new
    product_by_orden = @product_names_by_orden || {}
    labels = tab_labels_for(credits, resolver: resolver, product_by_orden: product_by_orden)

    credits.map.with_index do |credit, index|
      course_name = resolver.course_name_for_credit(credit, product_by_orden)
      student = build_student_summary(credit).merge(nombre_curso: course_name)

      {
        consecutivo_credito: credit["Consecutivo_credito"],
        label: labels[index],
        student: student,
        debt_summary: build_debt_summary(credit),
        cuotas: CuotaSelection.sorted(Array(credit["Cuotas"])),
        ordenes_pago: Array(credit["Ordenes_pago"]),
        credit: credit
      }
    end
  end

  def tab_labels_for(credits, resolver:, product_by_orden:)
    names = credits.map do |credit|
      resolver.course_name_for_credit(credit, product_by_orden).presence ||
        credit["Nombre_programa"].presence ||
        "Programa académico"
    end
    return names if names.uniq.size == names.size

    credits.map.with_index do |credit, index|
      base = names[index]
      period = credit["Nombre_periodo"].presence
      suffix = period || "Crédito #{credit['Consecutivo_credito']}"
      "#{base} (#{suffix})"
    end
  end

  def active_consecutivo_credito(tabs)
    requested = params[:consecutivo_credito].to_s
    return requested if tabs.any? { |tab| tab[:consecutivo_credito].to_s == requested }

    tabs.first&.dig(:consecutivo_credito).to_s
  end

  def build_student_summary(credit)
    credit ||= {}
    person_name = ::Q10::PersonName.from_hash(credit)
    nombre = person_name[:nombre].presence || @nombre
    apellido = person_name[:apellido].presence || @apellido

    {
      codigo_estudiante: credit["Codigo_estudiante"],
      nombre_completo: credit["Nombre_completo"].presence || [ nombre, apellido ].compact.join(" ").presence,
      nombre: nombre,
      apellido: apellido,
      numero_identificacion: credit["Numero_identificacion"],
      nombre_programa: credit["Nombre_programa"],
      nombre_periodo: credit["Nombre_periodo"],
      estado_credito: credit["Estado_credito"],
      numero_cuotas: credit["Numero_cuotas"],
      periodicidad_cuotas: credit["Periodicidad_cuotas"]
    }
  end

  def build_debt_summary(credit)
    credit ||= {}
    cuotas = Array(credit["Cuotas"])
    total_abonos = cuotas.sum { |cuota| to_decimal(cuota&.dig("Pagado")) || 0 }

    {
      deuda_total: to_decimal(credit["Valor_credito"]) || 0,
      total_abonos: total_abonos,
      total_pendiente: to_decimal(credit["Total_pendiente"]) || 0,
      pago_minimo: to_decimal(credit["Pago_minimo"] || credit["Pago_mínimo"]) || 0
    }
  end

  def to_decimal(value)
    case value
    when Numeric
      value.to_f
    when String
      cleaned = value.tr(",", ".").gsub(/[^\d.\-]/, "")
      return nil if cleaned.blank?

      cleaned.to_f
    end
  end
end
