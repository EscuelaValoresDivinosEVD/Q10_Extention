# frozen_string_literal: true

class AddCodigoEstudianteToPayments < ActiveRecord::Migration[8.0]
  def change
    add_column :payments, :codigo_estudiante, :string
  end
end
