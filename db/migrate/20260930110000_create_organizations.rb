class CreateOrganizations < ActiveRecord::Migration[8.1]
  # A organização é a unidade de isolamento: cada Master pertence a uma, cada conta comum
  # pertence a uma, e a conta da plataforma não pertence a nenhuma. Nasce sem nome — quem
  # a administra dá o nome no primeiro acesso.
  #
  # Dados que já existem (o berry tem Masters e anotações sem nenhum usuário) vão para uma
  # organização inicial sem nome, criada aqui só se houver o que abrigar: em banco vazio,
  # como o de teste, nada é inserido — o schema_integrity_test roda o seed num banco vazio
  # e nenhuma organização pode aparecer ali.
  def up
    create_table :organizations do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string :name, comment: "Nulo até o administrador da organização a nomear no primeiro acesso"
      t.timestamps
    end
    add_index :organizations, :uuid, unique: true
    add_index :organizations, :name, unique: true
    add_check_constraint :organizations, "name IS NULL OR length(btrim(name)) > 0",
      name: "organizations_name_not_blank"

    add_reference :channels, :organization, foreign_key: true
    add_reference :users, :organization, foreign_key: true
    add_reference :import_batches, :organization, foreign_key: true
    add_reference :access_grants, :organization, foreign_key: true
    add_column :users, :organization_admin, :boolean, null: false, default: false,
      comment: "Administra a própria organização inteira; só a plataforma atribui"

    backfill_initial_organization!

    change_column_null :channels, :organization_id, false
    change_column_null :import_batches, :organization_id, false
    change_column_null :access_grants, :organization_id, false

    # A conta da plataforma não pertence a organização nenhuma e não administra nenhuma;
    # toda outra conta pertence a exatamente uma. É o banco que garante, não só o modelo.
    add_check_constraint :users,
      "(platform_admin AND organization_id IS NULL AND NOT organization_admin) " \
      "OR (NOT platform_admin AND organization_id IS NOT NULL)",
      name: "users_platform_or_organization"

    # Alvos das FKs compostas: o par (id, organization_id) precisa ser único para ser
    # referenciado — o mesmo desenho de access_grants_channel_matches_sub_channel.
    add_index :channels, %i[id organization_id], unique: true
    add_index :users, %i[id organization_id], unique: true

    # Concessão só liga usuário e Master da mesma organização; lote só aponta para Master
    # da própria organização. Conceder ou importar carteira alheia é recusado pelo banco,
    # inclusive por console.
    add_foreign_key :access_grants, :channels,
      column: %i[channel_id organization_id], primary_key: %i[id organization_id],
      name: "access_grants_channel_in_organization"
    add_foreign_key :access_grants, :users,
      column: %i[user_id organization_id], primary_key: %i[id organization_id],
      name: "access_grants_user_in_organization"
    add_foreign_key :import_batches, :channels,
      column: %i[channel_id organization_id], primary_key: %i[id organization_id],
      name: "import_batches_channel_in_organization"
  end

  def down
    remove_foreign_key :import_batches, name: "import_batches_channel_in_organization"
    remove_foreign_key :access_grants, name: "access_grants_user_in_organization"
    remove_foreign_key :access_grants, name: "access_grants_channel_in_organization"
    remove_index :users, %i[id organization_id]
    remove_index :channels, %i[id organization_id]
    remove_check_constraint :users, name: "users_platform_or_organization"
    remove_column :users, :organization_admin
    remove_reference :access_grants, :organization
    remove_reference :import_batches, :organization
    remove_reference :users, :organization
    remove_reference :channels, :organization
    drop_table :organizations
  end

  private

  def backfill_initial_organization!
    precisa = %w[channels import_batches access_grants].any? { |t| select_value("SELECT 1 FROM #{t} LIMIT 1") } ||
      select_value("SELECT 1 FROM users WHERE NOT platform_admin LIMIT 1")
    return unless precisa

    id = select_value("INSERT INTO organizations (name, created_at, updated_at) VALUES (NULL, now(), now()) RETURNING id")
    execute "UPDATE channels SET organization_id = #{id} WHERE organization_id IS NULL"
    execute "UPDATE import_batches SET organization_id = #{id} WHERE organization_id IS NULL"
    execute "UPDATE users SET organization_id = #{id} WHERE organization_id IS NULL AND NOT platform_admin"
    execute "UPDATE access_grants SET organization_id = #{id} WHERE organization_id IS NULL"
  end
end
