# frozen_string_literal: true

module Ghl
  # Orquesta el reporte de una orden pagada a GoHighLevel y registra el resultado en la orden.
  # Espejo de Q10::ReportOrchestrator (flujo de deudas), con dos diferencias del PRD:
  #
  #   * son DOS llamadas (upsert + add tag), y `crm_reported` solo se marca si ambas salen bien
  #     (regla 5). Si el upsert va pero el tag falla, queda `crm_contact_id` guardado para que el
  #     reintento haga solo el paso del tag;
  #   * corre en background (CrmReportJob), no dentro del request del webhook — el reporte a Q10
  #     del flujo de deudas sí es síncrono (hallazgo QA-CONS-02); acá se evita ese acoplamiento.
  class ReportOrchestrator
    class << self
      def report_and_record!(order, client: Client.new)
        return skip(nil, "missing_order") if order.blank?
        return skip(order, "orden_no_pagada") unless order.pagada?
        return skip(order, "already_reported") if order.crm_reported?

        tag = order.tag_crm
        if tag.blank?
          return record(order, reported: false, error: "No se pudo calcular el tag curso-año de la orden.")
        end

        ejecutar(order, tag, client)
      end

      # Reintento manual por referencia: `Ghl::ReportOrchestrator.retry_report!("INSC-…")`.
      def retry_report!(reference, client: Client.new)
        order = OrderRecorder.fetch(reference)
        return false if order.blank? || !order.needs_crm_report?

        report_and_record!(order, client: client)[:reported].present?
      end

      # Barrido de órdenes pagadas sin reportar (job de reconciliación).
      def reconcile_all_pending!(scope: Order.crm_pendientes, client: Client.new)
        scope.order(:created_at).map do |order|
          { reference: order.reference, result: report_and_record!(order, client: client) }
        end
      end

      private

      def ejecutar(order, tag, client)
        contact_id = order.crm_contact_id.presence
        respuesta = {}

        # Paso 1 — upsert del contacto (se omite si un intento previo ya lo creó: regla 5).
        if contact_id.blank?
          upsert = client.upsert_contact(contact_payload(order, client))
          contact_id = upsert[:contact_id]
          respuesta = respuesta.merge(
            "upsert" => { "new" => upsert[:new], "traceId" => upsert[:trace_id], "contactId" => contact_id }
          )

          if contact_id.blank?
            return record(order, reported: false, response: respuesta,
                          error: "GoHighLevel no devolvió el id del contacto en el upsert.")
          end
        else
          respuesta = respuesta.merge("upsert" => { "omitido" => true, "contactId" => contact_id })
        end

        # Paso 2 — tag aditivo (no se manda en el upsert: ahí sobrescribiría los tags previos).
        tags = client.add_tags(contact_id: contact_id, tags: [ tag ])
        respuesta = respuesta.merge("tags" => tags[:tags])

        record(order, reported: true, contact_id: contact_id, tag: tag, response: respuesta)
      rescue Client::Error => e
        Rails.logger.error("[GHL] No se pudo reportar la orden #{order.reference}: #{e.message}")
        record(order, reported: false, contact_id: contact_id, response: respuesta, error: e.message)
      end

      def contact_payload(order, client)
        {
          firstName: order.first_name,
          lastName: order.last_name,
          email: order.email,
          phone: order.phone,
          address1: order.address,
          city: order.city,
          country: pais_alpha2(order),
          source: client.try(:source)
          # `tags` NO va acá: sobrescribiría los tags existentes del contacto.
        }
      end

      def pais_alpha2(order)
        alpha2 = CountryCodes.alpha2(order.country)
        if alpha2.blank? && order.country.present?
          Rails.logger.warn(
            "[GHL] País '#{order.country}' sin equivalente ISO alpha-2 (orden #{order.reference}); se envía sin país."
          )
        end
        alpha2
      end

      def record(order, reported:, contact_id: nil, tag: nil, response: {}, error: nil)
        resultado = {
          reported: reported,
          contact_id: contact_id,
          tag: tag,
          response: response,
          error: error
        }.compact

        OrderRecorder.apply_crm_report!(reference: order.reference, result: resultado)
        log_resultado(order.reference, resultado)
        resultado
      end

      def skip(order, reason)
        Rails.logger.info("[GHL] Reporte omitido para #{order&.reference || 'orden inexistente'}: #{reason}")
        { reported: reason == "already_reported", skipped: true, reason: reason }
      end

      def log_resultado(reference, resultado)
        if resultado[:reported]
          Rails.logger.info("[GHL] Orden #{reference} reportada al CRM con tag #{resultado[:tag]}.")
        else
          Rails.logger.warn("[GHL] Orden #{reference} no reportada: #{resultado[:error]}")
        end
      end
    end
  end
end
