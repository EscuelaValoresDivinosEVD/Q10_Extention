# frozen_string_literal: true

# Limita solicitudes al formulario de acceso: más de 15 intentos en 5 minutos
# desde el mismo dispositivo (IP) o usuario (correo) bloquea por 1 hora.
class AccessRateLimiter
  WINDOW = 5.minutes
  MAX_REQUESTS = 15
  BLOCK_DURATION = 1.hour
  NAMESPACE = "access_rate_limit"

  class << self
    def check!(request, email: nil)
      new.check!(request, email: email)
    end
  end

  def initialize(store: Rails.cache)
    @store = store
  end

  def check!(request, email: nil)
    identifiers_for(request, email).each do |identifier|
      return :blocked if blocked?(identifier)
      return :blocked if record_hit(identifier) == :blocked
    end

    :allowed
  end

  private

  def identifiers_for(request, email)
    ids = [ ip_identifier(request) ]
    normalized_email = email.to_s.strip.downcase
    ids << email_identifier(normalized_email) if normalized_email.present?
    ids
  end

  def blocked?(identifier)
    @store.exist?(block_key(identifier))
  end

  def record_hit(identifier)
    count = @store.increment(count_key(identifier), 1, expires_in: WINDOW)
    count = 1 if count.nil?

    if count > MAX_REQUESTS
      @store.write(block_key(identifier), true, expires_in: BLOCK_DURATION)
      :blocked
    else
      :allowed
    end
  end

  def ip_identifier(request)
    "ip:#{request.remote_ip}"
  end

  def email_identifier(email)
    "email:#{email}"
  end

  def count_key(identifier)
    "#{NAMESPACE}:count:#{identifier}"
  end

  def block_key(identifier)
    "#{NAMESPACE}:block:#{identifier}"
  end
end
