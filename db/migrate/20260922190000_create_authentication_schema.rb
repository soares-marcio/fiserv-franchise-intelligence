class CreateAuthenticationSchema < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string :email_address, null: false
      t.string :name, null: false
      t.string :password_digest, null: false
      t.boolean :super_admin, null: false, default: false
      # Lista fechada, validada contra Permission::KEYS — o mesmo desenho das faixas em
      # SubChannelCompensationRules: o catálogo mora no código, e o banco só recusa o que
      # não existe nele.
      t.string :permissions, array: true, null: false, default: []
      t.boolean :must_change_password, null: false, default: true
      # Segredo do TOTP, cifrado em repouso (Active Record Encryption). É texto porque o
      # que fica guardado é o envelope da criptografia, não os 32 caracteres base32.
      t.text :otp_secret
      t.datetime :mfa_enabled_at, comment: "Quando o usuário concluiu a inscrição do TOTP; nulo enquanto pendente"
      t.datetime :otp_last_used_at, comment: "Instante do último código aceito; impede reutilizar o mesmo código na janela"
      # Bloqueio por tentativa fica no banco, não no cache: o ambiente de teste usa
      # :null_store, e um bloqueio que não se consegue testar não existe.
      t.integer :failed_attempts, null: false, default: 0
      t.datetime :locked_until
      t.datetime :deactivated_at
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :users, :uuid, unique: true
    add_index :users, :email_address, unique: true
    add_check_constraint :users, "email_address = lower(email_address)", name: "users_email_downcased"
    # A lista sai de Permission::KEYS: o catálogo é um só, e o banco recusa chave que não
    # exista nele — inclusive vinda de console, seed ou job, que não passam pelo model.
    conhecidas = Permission::KEYS.map { |key| connection.quote(key) }.join(", ")
    add_check_constraint :users, "permissions <@ ARRAY[#{conhecidas}]::character varying[]",
      name: "users_permissions_known"

    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :ip_address
      t.string :user_agent
      t.datetime :last_active_at, null: false
      t.timestamps
    end
    add_index :sessions, :last_active_at

    # Um registro por código, porque cada um tem estado próprio: uso único exige saber
    # qual deles já foi gasto.
    create_table :recovery_codes do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :code_digest, null: false
      t.datetime :used_at
      t.timestamps
    end

    # Escopo de dados: cada linha é um Master inteiro (sub_channel_id nulo) ou um MIC.
    create_table :access_grants do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :channel, null: false, foreign_key: true
      t.references :sub_channel, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    # NULLS NOT DISTINCT: sem isso, duas concessões de Master inteiro para o mesmo usuário
    # passariam pelo índice, porque no Postgres nulo não é igual a nulo.
    add_index :access_grants, %i[user_id channel_id sub_channel_id],
      unique: true, nulls_not_distinct: true, name: "index_access_grants_unique"
    # A mesma guarda que map_snapshots e revenue_snapshots já usam: é o banco impedindo
    # conceder um MIC que pertence a outro Master.
    add_foreign_key :access_grants, :sub_channels,
      column: %i[sub_channel_id channel_id], primary_key: %i[id channel_id],
      name: "access_grants_channel_matches_sub_channel"

    # Liberação de lote a lote: quem não enviou o arquivo só o vê se for liberado aqui.
    create_table :batch_grants do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :import_batch, null: false, foreign_key: { on_delete: :cascade }
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :batch_grants, %i[user_id import_batch_id], unique: true

    # Trilha append-only: só created_at, e nada no código atualiza ou apaga linha daqui.
    # actor_email é instantâneo, para o registro sobreviver à exclusão do usuário.
    create_table :audit_events do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :actor_email, null: false
      t.string :action, null: false
      t.string :record_type
      t.bigint :record_id
      t.references :channel, foreign_key: true
      t.jsonb :metadata, null: false, default: {}
      t.string :ip_address
      t.datetime :created_at, null: false
    end
    add_index :audit_events, :created_at
    add_index :audit_events, %i[user_id created_at]
    add_index :audit_events, %i[record_type record_id]
    add_index :audit_events, %i[action created_at]

    # Autoria. Nulável e ON DELETE SET NULL de propósito: o histórico anterior ao login não
    # tem autor, e a receita de restauração do CLAUDE.md (restaurar só as anotações num
    # banco reimportado) não pode virar refém de uma FK rígida.
    add_reference :company_notes, :author, foreign_key: { to_table: :users, on_delete: :nullify }
    add_reference :import_batches, :uploaded_by, foreign_key: { to_table: :users, on_delete: :nullify }

    # Revisão do lote em quarentena.
    add_reference :import_batches, :reviewed_by, foreign_key: { to_table: :users, on_delete: :nullify }
    add_column :import_batches, :reviewed_at, :datetime
    add_column :import_batches, :review_note, :text,
      comment: "Motivo registrado por quem aprovou ou rejeitou o lote"
  end
end
