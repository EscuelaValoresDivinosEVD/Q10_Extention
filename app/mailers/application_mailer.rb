class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("APP_MAILER_FROM", "no-reply@evdsky.com")
  layout "mailer"
end
