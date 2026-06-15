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

ActiveRecord::Schema[8.0].define(version: 2026_06_06_130824) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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
    t.index ["consecutivo_credito"], name: "index_payments_on_consecutivo_credito"
    t.index ["created_at"], name: "index_payments_on_created_at"
    t.index ["numero_identificacion"], name: "index_payments_on_numero_identificacion"
    t.index ["reference"], name: "index_payments_on_reference", unique: true
    t.index ["status"], name: "index_payments_on_status"
  end
end
