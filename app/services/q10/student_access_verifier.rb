# frozen_string_literal: true

module Q10
  # Valida acceso contra GET /estudiantes/{id}
  # Respuesta oficial Q10: Email, Numero_identificacion, Codigo_estudiante, etc.
  class StudentAccessVerifier
    EMAIL_FIELD = "Email"
    IDENTIFICATION_TYPE_CODE_FIELDS = %w[
      Codigo_tipo_identificacion
      Código_tipo_identificacion
      Codigo_tipo_documento
      Código
      Codigo
    ].freeze

    def initialize(client: ApiClient.new)
      @client = client
    end

    def verify!(numero_identificacion:, email:, codigo_tipo_identificacion: nil)
      return { valid: true, skipped: true } unless @client.enabled?

      requested_id = normalize_identificacion(numero_identificacion)
      requested_type_code = normalize_code(codigo_tipo_identificacion)
      result = @client.fetch_estudiante(numero_identificacion: requested_id)
      estudiante = result[:data]

      unless estudiante.is_a?(Hash) && estudiante.present?
        return { valid: false, reason: :not_found }
      end

      unless identificacion_matches?(estudiante, requested_id)
        return { valid: false, reason: :not_found }
      end

      registered_email = extract_email(estudiante)
      return { valid: false, reason: :missing_email } if registered_email.blank?

      unless normalize_email(email) == normalize_email(registered_email)
        return { valid: false, reason: :email_mismatch }
      end

      if requested_type_code.blank?
        Rails.logger.warn("[Q10] Acceso sin codigo_tipo_identificacion para #{requested_id}")
        return { valid: false, reason: :missing_document_type }
      end

      registered_type_code = extract_identification_code(estudiante)
      if registered_type_code.blank?
        Rails.logger.warn("[Q10] Estudiante #{requested_id} sin Codigo_tipo_identificacion en Q10")
        return { valid: false, reason: :missing_document_type }
      end

      unless codes_match?(registered_type_code, requested_type_code)
        Rails.logger.info(
          "[Q10] Tipo identificación no coincide para #{requested_id}: " \
          "seleccionado=#{requested_type_code} registrado=#{registered_type_code}"
        )
        return { valid: false, reason: :document_type_mismatch }
      end

      { valid: true, estudiante: estudiante }
    rescue ApiClient::NotFoundError
      { valid: false, reason: :not_found }
    rescue ApiClient::Error => e
      { valid: false, reason: :api_error, detail: e.message }
    end

    private

    def identificacion_matches?(estudiante, requested_id)
      normalize_identificacion(estudiante["Numero_identificacion"]) == requested_id
    end

    def codes_match?(registered_code, requested_code)
      normalize_code(registered_code).casecmp?(normalize_code(requested_code))
    end

    def extract_identification_code(estudiante)
      IDENTIFICATION_TYPE_CODE_FIELDS.each do |field|
        value = estudiante[field]
        return value.to_s.strip if value.present?
      end

      estudiante.each do |key, candidate|
        next if candidate.blank?
        next if key.to_s.match?(/estudiante|persona|programa|periodo|pais|ciudad|lugar|genero|nombre|apellido|telefono|celular|email|correo|fecha|direccion|familiar/i)

        return candidate.to_s.strip if key.to_s.match?(/tipo.*identific.*c[oó]digo|c[oó]digo.*tipo.*identific/i)
      end

      nil
    end

    def extract_email(estudiante)
      value = estudiante[EMAIL_FIELD]
      return value if value.present?

      # Compatibilidad con respuestas antiguas o variantes del API.
      estudiante.each do |key, candidate|
        return candidate if key.to_s.match?(/correo|email/i) && candidate.present?
      end

      nil
    end

    def normalize_identificacion(value)
      value.to_s.strip.upcase
    end

    def normalize_email(value)
      value.to_s.strip.downcase
    end

    def normalize_code(value)
      value.to_s.strip
    end
  end
end
