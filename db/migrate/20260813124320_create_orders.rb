# frozen_string_literal: true

# Órdenes del funnel público de inscripción a cursos.
# Tabla nueva y aditiva: no toca `payments` ni el flujo de deudas Q10 (ver ADR-001 / ADR-011).
class CreateOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :orders do |t|
      # --- Identidad y estado ---
      t.string :reference, null: false
      t.string :status, null: false, default: "pending"
      t.string :return_token
      t.text   :error_message

      # --- Qué se compró: identificadores (SIN FK — no hay tabla local) + snapshot inmutable ---
      t.string  :q10_course_code, null: false   # viene de Q10 (Codigo)
      t.string  :option_code, null: false       # no viene de Q10 — fuente de precio pendiente
      t.string  :course_slug, null: false
      t.string  :course_name, null: false
      t.string  :option_kind, null: false
      t.string  :option_label, null: false
      t.integer :course_edition_year            # derivado de Fecha_inicio de Q10

      # --- Montos e IVA (invariante Pagomedios) — tax_rate fijo en 0.0 (ADR-004) ---
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string  :currency, null: false, default: "USD"
      t.decimal :amount_without_tax, precision: 12, scale: 2, null: false, default: 0.0
      t.decimal :amount_with_tax, precision: 12, scale: 2, null: false, default: 0.0
      t.decimal :tax_value, precision: 12, scale: 2, null: false, default: 0.0
      t.decimal :tax_rate, precision: 5, scale: 4, null: false, default: 0.0

      # --- Facturación (snapshot fiscal) — set de campos exigido por el SRI ---
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :identification_type_code, null: false
      t.string :identification_number, null: false
      t.string :email, null: false
      t.string :phone, null: false
      t.string :address, null: false
      t.string :city, null: false
      t.string :country, null: false

      # --- Transacción Pagomedios ---
      t.string   :pagomedios_token
      t.string   :payment_url
      t.string   :pagomedios_reference
      t.string   :authorization_code
      t.string   :card_number_masked           # SIEMPRE enmascarado por OrderRecorder (ADR-009)
      t.string   :card_brand
      t.string   :card_holder
      t.datetime :transaction_at
      t.string   :pagomedios_message
      t.jsonb    :pagomedios_payload, null: false, default: {}
      t.string   :invoice_number               # factura electrónica; nullable hasta que Pagomedios lo devuelva

      # --- Reporte al CRM (épica crm-gohighlevel) ---
      t.boolean  :crm_reported, null: false, default: false
      t.datetime :crm_reported_at
      t.string   :crm_contact_id
      t.string   :crm_tag
      t.jsonb    :crm_response, null: false, default: {}
      t.text     :crm_error

      t.timestamps
    end

    add_index :orders, :reference, unique: true
    add_index :orders, :return_token, unique: true, where: "return_token IS NOT NULL"
    add_index :orders, :status
    add_index :orders, :created_at
    add_index :orders, [ :status, :created_at ]     # consulta dominante del panel admin
    add_index :orders, :q10_course_code             # filtro por curso en el panel
    add_index :orders, :email
    add_index :orders, :identification_number

    # Índice parcial: solo las órdenes que el job de reconciliación CRM debe barrer.
    add_index :orders, :crm_reported,
              where: "status = 'paid' AND crm_reported = false",
              name: "index_orders_crm_pendientes"

    add_check_constraint :orders, "amount > 0", name: "chk_orders_amount_positivo"

    # Invariante exigido por la API de Pagomedios v2.
    add_check_constraint :orders,
                         "amount = amount_with_tax + amount_without_tax + tax_value",
                         name: "chk_orders_desglose_iva_cuadra"
  end
end
