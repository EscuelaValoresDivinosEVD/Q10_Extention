# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_08_13_124320) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "orders", force: :cascade do |t|
    t.string "reference", null: false
    t.string "status", default: "pending", null: false
    t.string "return_token"
    t.text "error_message"
    t.string "q10_course_code", null: false
    t.string "option_code", null: false
    t.string "course_slug", null: false
    t.string "course_name", null: false
    t.string "option_kind", null: false
    t.string "option_label", null: false
    t.integer "course_edition_year"
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.string "currency", default: "USD", null: false
    t.decimal "amount_without_tax", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "amount_with_tax", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "tax_value", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "tax_rate", precision: 5, scale: 4, default: "0.0", null: false
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.string "identification_type_code", null: false
    t.string "identification_number", null: false
    t.string "email", null: false
    t.string "phone", null: false
    t.string "address", null: false
    t.string "city", null: false
    t.string "country", null: false
    t.string "pagomedios_token"
    t.string "payment_url"
    t.string "pagomedios_reference"
    t.string "authorization_code"
    t.string "card_number_masked"
    t.string "card_brand"
    t.string "card_holder"
    t.datetime "transaction_at"
    t.string "pagomedios_message"
    t.jsonb "pagomedios_payload", default: {}, null: false
    t.string "invoice_number"
    t.boolean "crm_reported", default: false, null: false
    t.datetime "crm_reported_at"
    t.string "crm_contact_id"
    t.string "crm_tag"
    t.jsonb "crm_response", default: {}, null: false
    t.text "crm_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_orders_on_created_at"
    t.index ["crm_reported"], name: "index_orders_crm_pendientes", where: "(((status)::text = 'paid'::text) AND (crm_reported = false))"
    t.index ["email"], name: "index_orders_on_email"
    t.index ["identification_number"], name: "index_orders_on_identification_number"
    t.index ["q10_course_code"], name: "index_orders_on_q10_course_code"
    t.index ["reference"], name: "index_orders_on_reference", unique: true
    t.index ["return_token"], name: "index_orders_on_return_token", unique: true, where: "(return_token IS NOT NULL)"
    t.index ["status", "created_at"], name: "index_orders_on_status_and_created_at"
    t.index ["status"], name: "index_orders_on_status"
    t.check_constraint "amount = (amount_with_tax + amount_without_tax + tax_value)", name: "chk_orders_desglose_iva_cuadra"
    t.check_constraint "amount > 0::numeric", name: "chk_orders_amount_positivo"
  end

  create_table "payments", force: :cascade do |t|
    t.string "reference", null: false
    t.string "status", default: "pending", null: false
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.string "currency", default: "USD", null: false
    t.string "description"
    t.string "numero_identificacion"
    t.string "codigo_persona"
    t.string "codigo_cajero"
    t.integer "consecutivo_credito"
    t.jsonb "cuotas", default: [], null: false
    t.string "pagomedios_token"
    t.string "payment_url"
    t.string "pagomedios_reference"
    t.string "authorization_code"
    t.string "card_number_masked"
    t.string "card_brand"
    t.string "card_holder"
    t.datetime "transaction_at"
    t.string "pagomedios_message"
    t.jsonb "pagomedios_payload", default: {}, null: false
    t.boolean "q10_reported", default: false, null: false
    t.datetime "q10_reported_at"
    t.jsonb "q10_response", default: {}, null: false
    t.text "q10_error"
    t.text "error_message"
    t.string "return_token"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "codigo_estudiante"
    t.index ["consecutivo_credito"], name: "index_payments_on_consecutivo_credito"
    t.index ["created_at"], name: "index_payments_on_created_at"
    t.index ["numero_identificacion"], name: "index_payments_on_numero_identificacion"
    t.index ["reference"], name: "index_payments_on_reference", unique: true
    t.index ["status"], name: "index_payments_on_status"
  end
end
