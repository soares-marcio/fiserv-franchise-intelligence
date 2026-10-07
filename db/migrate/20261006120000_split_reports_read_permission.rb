# "Ver relatórios" abria os seis itens do menu de uma vez, e quem concedia pensava no link
# que a pessoa ia ver (homologação de 06/10/2026). A chave vira seis, uma por item.
#
# Quem tinha a chave antiga recebe as seis: ninguém perde tela nenhuma na troca. As listas
# ficam escritas aqui, e não lidas de Permission::KEYS, para a migration continuar dizendo a
# mesma coisa quando o catálogo mudar de novo.
class SplitReportsReadPermission < ActiveRecord::Migration[8.1]
  REPORT_KEYS = %w[reports_revenue reports_clover reports_weekly reports_three_months
    reports_recurring reports_indicators].freeze
  OTHER_KEYS = %w[reports_export establishments_read notes_read notes_write batches_read
    batches_upload batches_adjust batches_discard batches_approve metabase_read users_invite].freeze

  def up
    remove_check_constraint :users, name: "users_permissions_known"
    execute <<~SQL
      UPDATE users
         SET permissions = array_remove(permissions, 'reports_read') || #{array_sql(REPORT_KEYS)}
       WHERE 'reports_read' = ANY(permissions)
    SQL
    add_known_check(REPORT_KEYS + OTHER_KEYS)
  end

  def down
    remove_check_constraint :users, name: "users_permissions_known"
    execute <<~SQL
      UPDATE users
         SET permissions = ARRAY(
               SELECT key FROM unnest(permissions) AS key WHERE key <> ALL(#{array_sql(REPORT_KEYS)})
             )::character varying[] || ARRAY['reports_read']::character varying[]
       WHERE permissions && #{array_sql(REPORT_KEYS)}
    SQL
    add_known_check([ "reports_read" ] + OTHER_KEYS)
  end

  private

  def array_sql(keys)
    "ARRAY[#{keys.map { |key| connection.quote(key) }.join(', ')}]::character varying[]"
  end

  def add_known_check(keys)
    add_check_constraint :users, "permissions <@ #{array_sql(keys)}", name: "users_permissions_known"
  end
end
