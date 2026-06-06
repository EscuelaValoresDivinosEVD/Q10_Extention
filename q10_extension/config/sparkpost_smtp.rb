# frozen_string_literal: true

module SparkpostSmtp
  module_function

  def smtp_api_key
    ENV["SPARKPOST_SMTP_API_KEY"].presence ||
      Rails.application.credentials.dig(:sparkpost, :smtp_api_key)
  end

  def configured?
    smtp_api_key.present?
  end

  def settings
    {
      address: "smtp.sparkpostmail.com",
      port: 587,
      domain: "evdsky.com",
      user_name: "SMTP_Injection",
      password: smtp_api_key,
      authentication: :login,
      enable_starttls_auto: true,
      open_timeout: 30,
      read_timeout: 30
    }
  end
end
