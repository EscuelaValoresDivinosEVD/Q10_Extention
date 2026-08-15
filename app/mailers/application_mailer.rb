# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  BANNER_PATH = Rails.root.join("app/assets/images/mailers/banner_correos_clev.jpg")

  default from: ENV.fetch("APP_MAILER_FROM", "no-reply@evdsky.com")
  layout "mailer"

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
