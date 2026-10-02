class AddOrganizationToAuditEvents < ActiveRecord::Migration[8.1]
  # A trilha ganha a organização em que o evento aconteceu. Nulo é evento de plataforma —
  # criar organização, reiniciar o segundo fator de um administrador — e é só o que a
  # plataforma vê; cada organização vê os seus.
  #
  # Eventos antigos: a organização vem do ator quando ele tem uma, senão do canal do
  # evento. Login de conta da plataforma e tentativas sem usuário ficam nulos, que é o
  # que são. Sem FK com on_delete: organização não se apaga.
  def change
    add_reference :audit_events, :organization, foreign_key: true, index: false
    add_index :audit_events, %i[organization_id created_at]

    reversible do |direction|
      direction.up do
        execute <<~SQL
          UPDATE audit_events e
          SET organization_id = COALESCE(
            (SELECT u.organization_id FROM users u WHERE u.id = e.user_id),
            (SELECT c.organization_id FROM channels c WHERE c.id = e.channel_id)
          )
          WHERE e.organization_id IS NULL
        SQL
      end
    end
  end
end
