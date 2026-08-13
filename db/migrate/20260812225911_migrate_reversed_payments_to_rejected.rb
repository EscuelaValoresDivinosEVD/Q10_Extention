# frozen_string_literal: true

class MigrateReversedPaymentsToRejected < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL.squish
      UPDATE payments
      SET status = 'rejected', updated_at = CURRENT_TIMESTAMP
      WHERE status = 'reversed'
    SQL
  end

  def down
    # No se puede restaurar con certeza qué registros eran originalmente reversed.
  end
end
