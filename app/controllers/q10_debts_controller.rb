# frozen_string_literal: true

class Q10DebtsController < ApplicationController
  after_action :prevent_sensitive_page_cache, only: :show

  def show
    payload = ::Q10::LinkToken.verify(params[:token])
    @numero_identificacion = payload["numero_identificacion"] || payload["codigo_persona"]
    @student_email = payload.fetch("email")
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

    result = ::Q10::ApiClient.new.fetch_creditos(numero_identificacion: @numero_identificacion)
    @q10_payload = result[:data]
    @credits_list = extract_credits(@q10_payload)
    @program_tabs = build_program_tabs(@credits_list)
    @active_consecutivo = active_consecutivo_credito(@program_tabs)
    @student = build_student_summary(@credits_list.first || {})
    @blocked_cuotas_by_credit = PaymentCuotaLock.blocked_cuotas_by_credit(numero_identificacion: @numero_identificacion)

    if @program_tabs.empty?
      flash.now[:alert] = "No encontramos créditos activos en Q10 para esta persona."
      return render :show
    end
  rescue ::Q10::LinkToken::Error => e
    redirect_to root_path, alert: e.message
  rescue ::Q10::ApiClient::Error => e
    flash.now[:alert] = "No fue posible consultar los datos en Q10. #{e.message}"
    @q10_payload = {}
    @credits_list = []
    @program_tabs = []
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
    labels = tab_labels_for(credits)

    credits.map.with_index do |credit, index|
      {
        consecutivo_credito: credit["Consecutivo_credito"],
        label: labels[index],
        student: build_student_summary(credit),
        debt_summary: build_debt_summary(credit),
        cuotas: CuotaSelection.sorted(Array(credit["Cuotas"])),
        ordenes_pago: Array(credit["Ordenes_pago"]),
        credit: credit
      }
    end
  end

  def tab_labels_for(credits)
    names = credits.map { |credit| credit["Nombre_programa"].presence || "Programa académico" }
    return names if names.uniq.size == names.size

    credits.map do |credit|
      base = credit["Nombre_programa"].presence || "Programa académico"
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

    {
      codigo_estudiante: credit["Codigo_estudiante"],
      nombre_completo: credit["Nombre_completo"],
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
