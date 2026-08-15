# frozen_string_literal: true

class StudentAccessMailer < ApplicationMailer
  def continue_process(email:, continue_url:)
    @continue_url = continue_url
    attach_email_banner

    mail(
      to: email,
      subject: "Continúa tu proceso en el sistema CLEV"
    )
  end
end
