# frozen_string_literal: true

module Q10
  # Une créditos con /ordenespago (Estado=2) por Numero_orden_pago
  # para obtener Nombre_producto (nombre del curso) desde Detalles.
  class CourseNameResolver
    def initialize(client: ApiClient.new)
      @client = client
    end

    def product_names_by_orden(codigo_persona:)
      return {} if codigo_persona.blank? || !@client.enabled?

      result = @client.fetch_ordenes_pago(codigo_persona: codigo_persona, estado: 2)
      map = {}

      Array(result[:data]).each do |orden|
        next unless orden.is_a?(Hash)

        numero = orden["Numero_orden_pago"].to_s.strip
        next if numero.blank?

        product = first_product_name(orden)
        map[numero] = product if product.present?
      end

      map
    rescue ApiClient::Error => e
      Rails.logger.warn("[Q10] No se pudieron cargar órdenes de pago para cursos: #{e.message}")
      {}
    end

    def course_name_for_credit(credit, product_by_orden)
      return if credit.blank? || product_by_orden.blank?

      Array(credit["Ordenes_pago"]).each do |orden|
        next unless orden.is_a?(Hash)

        numero = orden["Numero_orden_pago"].to_s.strip
        name = product_by_orden[numero]
        return name if name.present?
      end

      nil
    end

    private

    def first_product_name(orden)
      Array(orden["Detalles"]).each do |detalle|
        next unless detalle.is_a?(Hash)

        name = detalle["Nombre_producto"].presence
        return name if name.present?
      end

      nil
    end
  end
end
