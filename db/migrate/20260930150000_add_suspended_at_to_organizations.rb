class AddSuspendedAtToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :suspended_at, :datetime,
      comment: "Suspensa pela plataforma: ninguém dela entra até a reativação; nada é apagado"
  end
end
