# frozen_string_literal: true

class CuotaReminderMailer < ApplicationMailer
  def upcoming_cuota(email:, student_name:, cuota:, continue_url:, days_before:)
    @student_name = student_name.presence || "estudiante"
    @cuota = cuota
    @continue_url = continue_url
    @days_before = days_before
    attach_email_banner

    days_label = days_before == 1 ? "día" : "días"
    subject = "Recordatorio: tu cuota ##{cuota[:numero]}#{curso_subject_suffix(cuota)} vence en #{days_before} #{days_label}"

    mail(to: email, subject: subject)
  end

  def overdue_cuota(email:, student_name:, cuota:, continue_url:)
    @student_name = student_name.presence || "estudiante"
    @cuota = cuota
    @continue_url = continue_url
    attach_email_banner

    mail(
      to: email,
      subject: "Cuota ##{cuota[:numero]}#{curso_subject_suffix(cuota)} vencida — realiza tu pago en CLEV"
    )
  end

  private

  def curso_subject_suffix(cuota)
    curso = cuota[:curso].to_s.strip
    curso.present? ? " del curso #{curso}" : ""
  end
end
