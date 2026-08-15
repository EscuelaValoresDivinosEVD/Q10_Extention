# frozen_string_literal: true

class CreateCuotaReminderDeliveries < ActiveRecord::Migration[8.0]
  def change
    create_table :cuota_reminder_deliveries do |t|
      t.string :numero_identificacion, null: false
      t.integer :consecutivo_credito
      t.string :numero_cuota, null: false
      t.date :fecha_cuota, null: false
      t.integer :days_before, null: false
      t.string :email, null: false
      t.datetime :sent_at, null: false

      t.timestamps
    end

    add_index :cuota_reminder_deliveries,
              [ :numero_identificacion, :consecutivo_credito, :numero_cuota, :fecha_cuota, :days_before ],
              unique: true,
              name: "index_cuota_reminder_deliveries_unique"
  end
end
