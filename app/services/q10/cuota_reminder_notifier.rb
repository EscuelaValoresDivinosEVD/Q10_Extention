# frozen_string_literal: true

module Q10
  # Envía dos tipos de aviso sobre la próxima cuota pendiente:
  # 1) Exactamente CUOTA_REMINDER_DAYS días antes del vencimiento.
  # 2) Un aviso único cuando la cuota ya está vencida.
  class CuotaReminderNotifier
    DEFAULT_DAYS = 5
    OVERDUE_MARKER = -1
    REMINDER_LINK_EXPIRES_IN = 7.days

    def initialize(client: ApiClient.new, periods: Periods.new, course_resolver: nil)
      @client = client
      @periods = periods
      @course_resolver = course_resolver || CourseNameResolver.new(client: client)
    end

    def self.reminder_days_before
      raw = ENV.fetch("CUOTA_REMINDER_DAYS", DEFAULT_DAYS.to_s).to_s.strip
      return DEFAULT_DAYS unless raw.match?(/\A\d+\z/)

      days = raw.to_i
      days.positive? ? days : DEFAULT_DAYS
    end

    def call
      return { sent: 0, skipped: 0, errors: 0 } unless @client.enabled?

      sent = 0
      skipped = 0
      errors = 0

      candidate_identifications.each do |numero_identificacion|
        result = process_student(numero_identificacion)
        sent += result[:sent]
        skipped += result[:skipped]
        errors += result[:errors]
      end

      { sent: sent, skipped: skipped, errors: errors }
    end

    private

    def candidate_identifications
      Payment.where.not(numero_identificacion: [ nil, "" ])
        .distinct
        .order(:numero_identificacion)
        .pluck(:numero_identificacion)
    end

    def process_student(numero_identificacion)
      sent = 0
      skipped = 0
      errors = 0

      estudiante = fetch_estudiante(numero_identificacion)
      email = extract_email(estudiante)
      if email.blank?
        Rails.logger.warn("[CuotaReminder] Sin correo Q10 para #{numero_identificacion}")
        return { sent: 0, skipped: 1, errors: 0 }
      end

      codigo_persona = if estudiante.is_a?(Hash)
        estudiante["Codigo_persona"].presence || estudiante["Codigo_estudiante"].presence
      end
      person_name = PersonName.from_hash(estudiante || {})
      student_name = [ person_name[:nombre], person_name[:apellido] ].compact.join(" ").presence

      credits = fetch_credits(numero_identificacion, codigo_persona)
      return { sent: 0, skipped: 1, errors: 0 } if credits.empty?

      product_by_orden = @course_resolver.product_names_by_orden(codigo_persona: codigo_persona)

      credits.each do |credit|
        next_cuota = next_pending_cuota(credit)
        next if next_cuota.blank?

        fecha = parse_date(next_cuota["Fecha_cuota"])
        next if fecha.blank?

        kind = reminder_kind_for(fecha)
        next if kind.blank?

        delivery_key = kind == :overdue ? OVERDUE_MARKER : self.class.reminder_days_before
        numero = CuotaSelection.numero(next_cuota)
        consecutivo = credit["Consecutivo_credito"]

        if already_sent?(numero_identificacion, consecutivo, numero, fecha, delivery_key)
          skipped += 1
          next
        end

        begin
          deliver_reminder!(
            kind: kind,
            email: email,
            student_name: student_name,
            numero_identificacion: numero_identificacion,
            codigo_persona: codigo_persona,
            credit: credit,
            cuota: next_cuota,
            fecha: fecha,
            days_before: delivery_key,
            curso: course_name_for(credit, product_by_orden)
          )
          sent += 1
        rescue StandardError => e
          errors += 1
          Rails.logger.error(
            "[CuotaReminder] Error enviando a #{numero_identificacion} " \
            "cuota #{numero}: #{e.class} #{e.message}"
          )
        end
      end

      { sent: sent, skipped: skipped, errors: errors }
    rescue StandardError => e
      Rails.logger.error("[CuotaReminder] Error procesando #{numero_identificacion}: #{e.class} #{e.message}")
      { sent: 0, skipped: 0, errors: 1 }
    end

    def reminder_kind_for(fecha)
      days_until = (fecha - Date.current).to_i
      return :upcoming if days_until == self.class.reminder_days_before
      return :overdue if days_until.negative?

      nil
    end

    def fetch_estudiante(numero_identificacion)
      @client.fetch_estudiante(numero_identificacion: numero_identificacion)[:data]
    rescue ApiClient::NotFoundError
      nil
    end

    def fetch_credits(numero_identificacion, codigo_persona)
      result = @client.fetch_creditos(
        numero_identificacion: numero_identificacion,
        codigo_persona: codigo_persona,
        consecutivo_periodo: @periods.default_consecutivo
      )
      extract_credits(result[:data])
    rescue ApiClient::Error => e
      Rails.logger.warn("[CuotaReminder] No se pudieron consultar créditos de #{numero_identificacion}: #{e.message}")
      []
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

    def next_pending_cuota(credit)
      CuotaSelection.sorted(Array(credit["Cuotas"])).find { |cuota| CuotaSelection.pendiente?(cuota) }
    end

    def parse_date(raw)
      return if raw.blank?

      Date.parse(raw.to_s.first(10))
    rescue ArgumentError, TypeError
      nil
    end

    def extract_email(estudiante)
      return if estudiante.blank?

      estudiante["Email"].presence || estudiante.values.find { |v| v.to_s.match?(URI::MailTo::EMAIL_REGEXP) }
    end

    def course_name_for(credit, product_by_orden)
      @course_resolver.course_name_for_credit(credit, product_by_orden).presence ||
        credit["Nombre_programa"].presence
    end

    def already_sent?(numero_identificacion, consecutivo, numero, fecha, days_before)
      CuotaReminderDelivery.exists?(
        numero_identificacion: numero_identificacion.to_s.strip,
        consecutivo_credito: consecutivo,
        numero_cuota: numero.to_s,
        fecha_cuota: fecha,
        days_before: days_before
      )
    end

    def deliver_reminder!(kind:, email:, student_name:, numero_identificacion:, codigo_persona:, credit:, cuota:, fecha:, days_before:, curso:)
      numero = CuotaSelection.numero(cuota)
      continue_url = build_continue_url(
        numero_identificacion: numero_identificacion,
        email: email,
        codigo_persona: codigo_persona
      )

      cuota_payload = {
        numero: numero,
        fecha: I18n.l(fecha),
        pendiente: format_money(cuota["Pendiente"]),
        curso: curso,
        periodo: credit["Nombre_periodo"].presence
      }

      mailer = CuotaReminderMailer
      if kind == :overdue
        mailer.overdue_cuota(
          email: email,
          student_name: student_name,
          continue_url: continue_url,
          cuota: cuota_payload
        ).deliver_now
      else
        mailer.upcoming_cuota(
          email: email,
          student_name: student_name,
          days_before: self.class.reminder_days_before,
          continue_url: continue_url,
          cuota: cuota_payload
        ).deliver_now
      end

      CuotaReminderDelivery.create!(
        numero_identificacion: numero_identificacion.to_s.strip,
        consecutivo_credito: credit["Consecutivo_credito"],
        numero_cuota: numero.to_s,
        fecha_cuota: fecha,
        days_before: days_before,
        email: email,
        sent_at: Time.current
      )
    end

    def build_continue_url(numero_identificacion:, email:, codigo_persona:)
      token = LinkToken.generate(
        {
          numero_identificacion: numero_identificacion,
          email: email,
          codigo_persona: codigo_persona,
          consecutivo_periodo: @periods.default_consecutivo
        }.compact,
        expires_in: REMINDER_LINK_EXPIRES_IN
      )

      Rails.application.routes.url_helpers.q10_continue_url(
        token: token,
        **ActionMailer::Base.default_url_options
      )
    end

    def format_money(value)
      amount = value.to_f.round(2)
      format("$%.2f", amount)
    end
  end
end
