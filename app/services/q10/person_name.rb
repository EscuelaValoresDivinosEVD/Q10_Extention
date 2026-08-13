# frozen_string_literal: true

module Q10
  # Extrae nombre y apellido desde payloads de estudiante o crédito Q10.
  class PersonName
    class << self
      def from_hash(payload)
        hash = payload.is_a?(Hash) ? payload.deep_stringify_keys : {}

        nombre = join_parts(hash["Primer_nombre"], hash["Segundo_nombre"]) ||
                 hash["nombre"].to_s.strip.presence
        apellido = join_parts(hash["Primer_apellido"], hash["Segundo_apellido"]) ||
                   hash["apellido"].to_s.strip.presence

        if nombre.blank? && apellido.blank?
          full = hash["Nombre_completo"].presence || hash["nombre_completo"].presence
          nombre, apellido = split_nombre_completo(full)
        end

        { nombre: nombre, apellido: apellido }
      end

      private

      def join_parts(*parts)
        parts.map { |part| part.to_s.strip.presence }.compact.join(" ").presence
      end

      # Si solo hay Nombre_completo, se guarda entero en nombre.
      def split_nombre_completo(full)
        return [ nil, nil ] if full.blank?

        [ full.to_s.strip, nil ]
      end
    end
  end
end
