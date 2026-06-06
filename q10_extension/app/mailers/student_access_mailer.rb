# frozen_string_literal: true

class StudentAccessMailer < ApplicationMailer
  default from: ENV.fetch("APP_MAILER_FROM", "no-reply@evdsky.com")

  def continue_process(email:, continue_url:)
    @continue_url = continue_url
    mail(
      to: email,
      subject: "Continua tu proceso en el sistema CLEV"
    )
  end
end
