# frozen_string_literal: true

class CreatePayments < ActiveRecord::Migration[8.0]
  def change
    create_table :payments do |t|
      t.string :reference, null: false
      t.string :status, null: false, default: "pending"
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :currency, null: false, default: "USD"
      t.string :description
      t.string :numero_identificacion
      t.string :codigo_persona
      t.string :codigo_cajero
      t.integer :consecutivo_credito
      t.jsonb :cuotas, null: false, default: []
      t.string :pagomedios_token
      t.string :payment_url
      t.string :pagomedios_reference
      t.string :authorization_code
      t.string :card_number_masked
      t.string :card_brand
      t.string :card_holder
      t.datetime :transaction_at
      t.string :pagomedios_message
      t.jsonb :pagomedios_payload, null: false, default: {}
      t.boolean :q10_reported, null: false, default: false
      t.datetime :q10_reported_at
      t.jsonb :q10_response, null: false, default: {}
      t.text :q10_error
      t.text :error_message
      t.string :return_token

      t.timestamps
    end

    add_index :payments, :reference, unique: true
    add_index :payments, :status
    add_index :payments, :numero_identificacion
    add_index :payments, :consecutivo_credito
    add_index :payments, :created_at
  end
end
