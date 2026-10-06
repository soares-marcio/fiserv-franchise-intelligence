# Validade do acesso (pedido da administradora da organização, 06/10/2026): nula é tempo
# indeterminado, que é como toda conta existente continua. Data, e não instante: o acesso
# vale até o fim do dia escolhido, no horário de Brasília (config.time_zone).
class AddAccessExpiresOnToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :access_expires_on, :date,
      comment: "Último dia em que a pessoa entra; nulo é tempo indeterminado"
  end
end
