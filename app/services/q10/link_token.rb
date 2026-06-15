# frozen_string_literal: true

module Q10
  class LinkToken
    PURPOSE = "q10-continue-link"
    EXPIRES_IN = 2.hours

    class Error < StandardError; end

    def self.generate(payload)
      verifier.generate(payload, purpose: PURPOSE, expires_in: EXPIRES_IN)
    end

    def self.verify(token)
      verifier.verify(token, purpose: PURPOSE)
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      raise Error, "El enlace es inválido o ya expiró."
    end

    def self.verifier
      secret = Rails.application.secret_key_base
      ActiveSupport::MessageVerifier.new(secret, digest: "SHA256", serializer: JSON)
    end
    private_class_method :verifier
  end
end
