class AddNombreApellidoToPayments < ActiveRecord::Migration[8.0]
  def change
    add_column :payments, :nombre, :string
    add_column :payments, :apellido, :string
  end
end
