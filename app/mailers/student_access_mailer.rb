# frozen_string_literal: true

class StudentAccessMailer < ApplicationMailer
  BANNER_PATH = Rails.root.join("app/assets/images/mailers/banner_correos_clev.jpg")

  def continue_process(email:, continue_url:)
    @continue_url = continue_url
    attach_email_banner

    mail(
      to: email,
      subject: "Continúa tu proceso en el sistema CLEV"
    )
  end

  private

  def attach_email_banner
    return unless BANNER_PATH.exist?

    attachments.inline["banner_correos_clev.jpg"] = {
      mime_type: "image/jpeg",
      content: File.binread(BANNER_PATH)
    }
    @banner_cid = attachments["banner_correos_clev.jpg"].url
  end
end
