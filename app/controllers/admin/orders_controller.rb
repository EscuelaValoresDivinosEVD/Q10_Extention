# frozen_string_literal: true

require "csv"

module Admin
  # Panel de órdenes del funnel de inscripción (/admin/ordenes). Vive junto a /admin/pagos, con la
  # misma autenticación HTTP Basic, pero consulta otra tabla: no hay vista unificada en v1.
  class OrdersController < ApplicationController
    include AdminBasicAuth

    POR_PAGINA = 50
    LOTE_CSV = 500

    # Columnas del CSV: las 18 del PRD v1 + las 3 de estado del reporte CRM (v2) + el código de
    # curso de Q10, que es lo que permite conciliar contra la oferta académica.
    COLUMNAS_CSV = %w[
      referencia curso codigo_curso opcion monto moneda estado
      fecha_intento fecha_pago tipo_identificacion numero_identificacion
      nombre apellido correo telefono direccion ciudad pais numero_factura
      estado_crm tag_crm contacto_crm
    ].freeze

    def index
      @filtro = OrderFilter.new(filtro_params)
      @ordenes_scope = @filtro.scope
      @resumen = @filtro.scope_para_resumen.group(:status).count
      @cursos = cursos_para_filtro

      respond_to do |format|
        format.html { preparar_listado }
        format.csv { enviar_csv }
      end
    end

    def show
      @order = Order.find(params[:id])
      @tipo_identificacion = tipos_identificacion[@order.identification_type_code]
    end

    private

    def preparar_listado
      @total = @ordenes_scope.count
      @total_paginas = [ (@total.to_f / POR_PAGINA).ceil, 1 ].max
      @pagina = params[:pagina].to_i.clamp(1, @total_paginas)
      @ordenes = @ordenes_scope.limit(POR_PAGINA).offset((@pagina - 1) * POR_PAGINA)
    end

    def enviar_csv
      send_data generar_csv(@ordenes_scope),
                filename: @filtro.nombre_archivo,
                type: "text/csv; charset=utf-8",
                disposition: "attachment"
    end

    # Regla 5: no cargar todo en memoria. `find_each` recorre en lotes; el orden por PK que impone
    # es aceptable para un export (el listado en pantalla sí va por fecha desc).
    def generar_csv(scope)
      etiquetas = tipos_identificacion

      csv = CSV.generate(headers: true) do |salida|
        salida << COLUMNAS_CSV
        scope.reorder(:id).find_each(batch_size: LOTE_CSV) do |order|
          salida << fila_csv(order, etiquetas)
        end
      end

      # BOM para que Excel abra los acentos correctamente (regla 6).
      "﻿#{csv}"
    end

    def fila_csv(order, etiquetas)
      [
        order.reference,
        order.course_name,
        order.q10_course_code,
        order.option_label,
        format("%.2f", order.amount),
        order.currency,
        helpers.order_status_label(order.status),
        formato_fecha(order.created_at),
        formato_fecha(order.transaction_at),
        etiquetas[order.identification_type_code] || order.identification_type_code,
        order.identification_number,
        order.first_name,
        order.last_name,
        order.email,
        order.phone,
        order.address,
        order.city,
        order.country,
        order.invoice_number,
        helpers.order_crm_label(order),
        order.crm_tag,
        order.crm_contact_id
      ]
    end

    def formato_fecha(fecha)
      return nil if fecha.blank?

      fecha.in_time_zone.strftime("%Y-%m-%d %H:%M")
    end

    # El dropdown de cursos se arma con el histórico de órdenes: ya no hay tabla `courses` contra
    # la cual hacer join (ADR-008). Muestra lo que alguna vez se compró, no la oferta vigente.
    def cursos_para_filtro
      Order.distinct.pluck(:q10_course_code, :course_name)
           .map { |codigo, nombre| [ nombre.presence || codigo, codigo ] }
           .sort_by { |nombre, _codigo| nombre.to_s }
    end

    def tipos_identificacion
      @tipos_identificacion ||= ::Q10::IdentificationTypes.new.all.index_by { |tipo| tipo[:code] }
                                                          .transform_values { |tipo| tipo[:name] }
    end

    def filtro_params
      params.permit(:estado, :curso, :desde, :hasta, :crm).to_h.symbolize_keys
    end
  end
end
