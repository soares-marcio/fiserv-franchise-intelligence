class CreateBinReportingSchema < ActiveRecord::Migration[8.1]
  def change
    enable_extension 'plpgsql'
    enable_extension 'pgcrypto'
    enable_extension 'pg_trgm'
    enable_extension 'unaccent'
    enable_extension 'vector'

    create_table :channels do |t|
      t.uuid :uuid, null: false, default: -> { 'gen_random_uuid()' }
      t.string :external_id, null: false
      t.string :canal, null: false
      t.timestamps
    end
    add_index :channels, :uuid, unique: true
    add_index :channels, :external_id, unique: true
    add_index :channels, :canal, using: :gin, opclass: :gin_trgm_ops

    create_table :sub_channels do |t|
      t.uuid :uuid, null: false, default: -> { 'gen_random_uuid()' }
      t.references :channel, null: false, foreign_key: true
      t.string :sub_canal, null: false
      t.timestamps
    end
    add_index :sub_channels, :uuid, unique: true
    add_index :sub_channels, %i[channel_id sub_canal], unique: true
    add_index :sub_channels, %i[id channel_id], unique: true
    add_index :sub_channels, :sub_canal, using: :gin, opclass: :gin_trgm_ops

    create_table :companies do |t|
      t.uuid :uuid, null: false, default: -> { 'gen_random_uuid()' }
      t.string :cnpj, limit: 14, null: false
      t.timestamps
    end
    add_index :companies, :uuid, unique: true
    add_index :companies, :cnpj, unique: true
    add_check_constraint :companies, "cnpj ~ '^[0-9]{14}$'", name: 'companies_cnpj_format'

    create_table :establishments do |t|
      t.uuid :uuid, null: false, default: -> { 'gen_random_uuid()' }
      t.string :ec, limit: 8, null: false
      t.references :company, null: false, foreign_key: true
      t.references :channel, null: false, foreign_key: true
      t.references :primary_establishment, foreign_key: { to_table: :establishments }
      t.string :duplicate_reason
      t.string :duplicate_confirmed_by
      t.datetime :duplicate_confirmed_at
      t.timestamps
    end
    add_index :establishments, :uuid, unique: true
    add_index :establishments, :ec, unique: true
    add_index :establishments, %i[channel_id company_id]
    add_check_constraint :establishments, "ec ~ '^[0-9]{8}$'", name: 'establishments_ec_format'
    add_check_constraint :establishments,
      'primary_establishment_id IS NULL OR primary_establishment_id <> id',
      name: 'establishments_not_self_primary'

    create_table :import_templates do |t|
      t.string :name, null: false
      t.jsonb :sheet_names, null: false, default: []
      t.timestamps
    end
    add_index :import_templates, :name, unique: true

    create_table :import_template_columns do |t|
      t.references :import_template, null: false, foreign_key: true
      t.string :sheet_name, null: false
      t.string :source_header, null: false
      t.string :target_table
      t.string :target_field
      t.boolean :required, null: false, default: false
      t.string :normalization_rule
      t.timestamps
    end
    add_index :import_template_columns, %i[import_template_id sheet_name source_header],
      unique: true, name: 'index_template_columns_on_template_sheet_header'

    create_table :import_batches do |t|
      t.uuid :uuid, null: false, default: -> { 'gen_random_uuid()' }
      t.references :channel, null: false, foreign_key: true
      t.references :import_template, null: false, foreign_key: true
      t.string :source_filename, null: false
      t.date :source_file_date
      t.string :file_checksum, null: false
      t.date :competencia_m1
      t.date :competencia_atual
      t.jsonb :competencias_cobertas, null: false, default: []
      t.integer :dia_corte_mes_atual
      t.string :status, null: false, default: 'pending'
      t.jsonb :validation_errors, null: false, default: []
      t.timestamps
    end
    add_index :import_batches, :uuid, unique: true
    add_index :import_batches, :file_checksum, unique: true
    add_index :import_batches, %i[channel_id competencia_atual]
    add_check_constraint :import_batches, "status IN ('pending', 'validated', 'failed', 'superseded')",
      name: 'import_batches_valid_status'
    add_check_constraint :import_batches, 'dia_corte_mes_atual BETWEEN 1 AND 31',
      name: 'import_batches_valid_cutoff'

    create_table :revenue_snapshots do |t|
      t.references :import_batch, null: false, foreign_key: true
      t.references :channel, null: false, foreign_key: true
      t.references :establishment, null: false, foreign_key: true
      t.references :sub_channel, null: false, foreign_key: true
      t.string :hierarquia_origem
      t.string :razao_social
      t.string :nome_fantasia
      t.string :status_contrato
      t.date :data_suspensao
      t.date :data_ult_transacao
      t.boolean :ativo_ultimos_60_dias
      t.string :endereco
      t.string :cep
      t.string :cep_raw
      t.string :cidade
      t.string :estado
      t.string :telefone_trabalho
      t.string :telefone_raw
      t.string :cnae_codigo
      t.string :cnae_descricao
      t.decimal :fat_total_m1, precision: 18, scale: 2, null: false, default: 0
      t.decimal :fat_total_mes_atual, precision: 18, scale: 2, null: false, default: 0
      t.timestamps
    end
    add_index :revenue_snapshots, %i[import_batch_id establishment_id], unique: true
    add_index :revenue_snapshots, %i[channel_id sub_channel_id]

    create_table :map_snapshots do |t|
      t.references :import_batch, null: false, foreign_key: true
      t.references :channel, null: false, foreign_key: true
      t.references :establishment, null: false, foreign_key: true
      t.references :sub_channel, null: false, foreign_key: true
      t.string :hierarquia_origem
      t.string :tipo_pessoa
      t.string :razao_social
      t.string :nome_fantasia
      t.string :ramo_atividade
      t.string :cnae_codigo
      t.string :cnae_descricao
      t.string :status_contrato
      t.text :melhor_conversa_raw
      t.string :telefone_trabalho
      t.string :endereco
      t.string :cep
      t.string :nome_contato_1
      t.string :nome_contato_2
      t.string :cidade
      t.string :estado
      t.boolean :ilha_pj_mais
      t.datetime :vip_boarding_date
      t.string :motivo_entrada_vip
      t.string :segmento_presumido
      t.string :segmento_performado
      t.string :status_reciprocidade
      t.decimal :faturamento_medio_3m, precision: 18, scale: 2
      t.decimal :maior_faturamento, precision: 18, scale: 2
      t.decimal :diferenca_fat_m1_m2, precision: 18, scale: 2
      t.decimal :diferenca_fat_pct, precision: 12, scale: 4
      t.string :cluster_queda_fat
      t.boolean :ativo_mes_atual
      t.boolean :ativo_ultimo_mes
      t.boolean :ativo_ultimos_30_dias
      t.date :data_ult_transacao
      t.date :data_credenciamento
      t.date :data_instalacao
      t.date :data_ativacao
      t.date :data_suspensao
      t.datetime :ultimo_acesso_app
      t.string :solucoes_financeiras
      t.string :status_antecip_auto_boarding
      t.string :status_antecip_auto_boarding_2
      t.decimal :volume_pre_aprovado, precision: 18, scale: 2
      t.integer :prazo_pre_aprovado
      t.decimal :taxa_pre_aprovada, precision: 12, scale: 4
      t.decimal :parcela_pre_aprovada, precision: 18, scale: 2
      t.boolean :possui_link_pgto
      %i[tap_on_phone smart_pos demais_pos mps pin tef outros_terminais total_terminais].each do |terminal|
        t.integer "qtde_#{terminal}"
      end
      t.decimal :net_mdr, precision: 12, scale: 4
      t.string :net_mdr_status
      t.string :agenda_semanal
      t.timestamps
    end
    add_index :map_snapshots, %i[import_batch_id establishment_id], unique: true
    add_index :map_snapshots, %i[channel_id sub_channel_id]
    %i[razao_social nome_fantasia cidade].each { |column| add_index :map_snapshots, column, using: :gin, opclass: :gin_trgm_ops }

    create_table :activation_proposals do |t|
      t.references :import_batch, null: false, foreign_key: true
      t.references :channel, null: false, foreign_key: true
      t.references :sub_channel, null: false, foreign_key: true
      t.references :company, null: false, foreign_key: true
      t.references :establishment, foreign_key: true
      t.string :hierarquia_origem
      t.string :nr_da_proposta, null: false
      t.string :razao_social
      t.string :nome_fantasia
      t.string :status_proposta
      t.date :data_proposta
      t.date :data_afiliacao
      t.date :data_instalacao
      t.date :data_ativacao
      t.decimal :ticket_medio, precision: 18, scale: 2
      t.decimal :faturamento_anual_previsto, precision: 18, scale: 2
      t.timestamps
    end
    add_index :activation_proposals, %i[import_batch_id nr_da_proposta], unique: true
    add_index :activation_proposals, :nr_da_proposta

    create_table :monthly_volumes do |t|
      t.references :import_batch, null: false, foreign_key: true
      t.references :channel, null: false, foreign_key: true
      t.references :establishment, null: false, foreign_key: true
      t.date :competencia, null: false
      t.string :metrica, null: false
      t.decimal :amount, precision: 18, scale: 2, null: false
      t.timestamps
    end
    add_index :monthly_volumes, %i[import_batch_id establishment_id competencia metrica], unique: true,
      name: 'index_monthly_volumes_on_batch_establishment_competencia_metric'
    add_index :monthly_volumes, %i[channel_id competencia]

    execute <<~SQL
      CREATE TABLE daily_revenues (
        id bigserial NOT NULL,
        import_batch_id bigint NOT NULL REFERENCES import_batches(id),
        channel_id bigint NOT NULL REFERENCES channels(id),
        establishment_id bigint NOT NULL REFERENCES establishments(id),
        competencia date NOT NULL,
        day integer NOT NULL,
        amount numeric(18,2) NOT NULL,
        provisional boolean NOT NULL,
        created_at timestamp(6) without time zone NOT NULL,
        updated_at timestamp(6) without time zone NOT NULL,
        CONSTRAINT daily_revenues_valid_day CHECK (day BETWEEN 1 AND 31)
      ) PARTITION BY RANGE (competencia);
      CREATE TABLE daily_revenues_default PARTITION OF daily_revenues DEFAULT;
    SQL
    add_index :daily_revenues, %i[import_batch_id establishment_id competencia day], unique: true,
      name: 'index_daily_revenues_unique_snapshot_day'
    add_index :daily_revenues, %i[channel_id competencia day]
    add_index :daily_revenues, :import_batch_id
    add_index :daily_revenues, :channel_id
    add_index :daily_revenues, :establishment_id

    create_table :daily_revenues_consolidated, id: false do |t|
      t.references :establishment, null: false, foreign_key: true
      t.references :channel, null: false, foreign_key: true
      t.date :competencia, null: false
      t.integer :day, null: false
      t.decimal :amount, precision: 18, scale: 2, null: false
      t.boolean :provisional, null: false
      t.references :source_import_batch, null: false, foreign_key: { to_table: :import_batches }
      t.integer :revised_count, null: false, default: 0
      t.timestamps
    end
    add_index :daily_revenues_consolidated, %i[establishment_id competencia day], unique: true,
      name: 'index_daily_revenues_consolidated_primary'
    add_index :daily_revenues_consolidated, %i[channel_id competencia day]

    create_table :monthly_volumes_consolidated, id: false do |t|
      t.references :channel, null: false, foreign_key: true
      t.references :establishment, null: false, foreign_key: true
      t.date :competencia, null: false
      t.string :metrica, null: false
      t.decimal :amount, precision: 18, scale: 2, null: false
      t.references :source_import_batch, null: false, foreign_key: { to_table: :import_batches }
      t.timestamps
    end
    add_index :monthly_volumes_consolidated, %i[establishment_id competencia metrica], unique: true,
      name: 'index_monthly_volumes_consolidated_primary'
    add_index :monthly_volumes_consolidated, %i[channel_id competencia]

    create_table :competencia_coverages, id: false do |t|
      t.references :channel, null: false, foreign_key: true
      t.date :competencia, null: false
      t.integer :max_dia_conhecido, null: false
      t.boolean :fechado, null: false, default: false
      t.references :ultimo_import_batch, null: false, foreign_key: { to_table: :import_batches }
      t.timestamps
    end
    add_index :competencia_coverages, %i[channel_id competencia], unique: true

    add_foreign_key :revenue_snapshots, :sub_channels,
      column: %i[sub_channel_id channel_id], primary_key: %i[id channel_id],
      name: "revenue_snapshots_channel_matches_sub_channel"
    add_foreign_key :map_snapshots, :sub_channels,
      column: %i[sub_channel_id channel_id], primary_key: %i[id channel_id],
      name: "map_snapshots_channel_matches_sub_channel"
    add_foreign_key :activation_proposals, :sub_channels,
      column: %i[sub_channel_id channel_id], primary_key: %i[id channel_id],
      name: "activation_proposals_channel_matches_sub_channel"

    create_table :daily_revenue_revisions do |t|
      t.references :establishment, null: false, foreign_key: true
      t.date :competencia, null: false
      t.integer :day, null: false
      t.decimal :amount_anterior, precision: 18, scale: 2, null: false
      t.decimal :amount_novo, precision: 18, scale: 2, null: false
      t.references :import_batch, null: false, foreign_key: true
      t.datetime :detected_at, null: false
    end

    create_table :conversation_actions do |t|
      t.string :texto, null: false
      t.timestamps
    end
    add_index :conversation_actions, :texto, unique: true

    create_table :map_snapshot_actions do |t|
      t.references :map_snapshot, null: false, foreign_key: true
      t.references :conversation_action, null: false, foreign_key: true
      t.integer :posicao, null: false
    end
    add_index :map_snapshot_actions, %i[map_snapshot_id conversation_action_id], unique: true,
      name: 'index_map_snapshot_actions_unique_action'

    create_table :raw_import_rows do |t|
      t.references :import_batch, null: false, foreign_key: true
      t.string :sheet_name, null: false
      t.integer :row_number, null: false
      t.jsonb :payload, null: false
      t.timestamps
    end
    add_index :raw_import_rows, %i[import_batch_id sheet_name row_number], unique: true,
      name: 'index_raw_import_rows_unique_source_row'

    create_table :data_anomalies do |t|
      t.uuid :uuid, null: false, default: -> { 'gen_random_uuid()' }
      t.references :channel, null: false, foreign_key: true
      t.string :anomaly_type, null: false
      t.string :severity, null: false
      t.references :company, foreign_key: true
      t.references :establishment, foreign_key: true
      t.jsonb :details, null: false, default: {}
      t.string :status, null: false, default: 'aberta'
      t.datetime :first_detected_at, null: false
      t.datetime :last_detected_at, null: false
      t.integer :occurrences, null: false, default: 1
      t.references :first_import_batch, null: false, foreign_key: { to_table: :import_batches }
      t.references :last_import_batch, null: false, foreign_key: { to_table: :import_batches }
      t.string :resolved_by
      t.datetime :resolved_at
      t.text :resolution_note
      t.timestamps
    end
    add_index :data_anomalies, :uuid, unique: true
    add_index :data_anomalies, %i[channel_id anomaly_type company_id establishment_id], unique: true,
      nulls_not_distinct: true, name: 'index_data_anomalies_deduplication'
    add_check_constraint :data_anomalies, "severity IN ('info', 'atencao', 'erro')",
      name: "data_anomalies_valid_severity"
    add_check_constraint :data_anomalies, "status IN ('aberta', 'em_analise', 'resolvida', 'esperada')",
      name: "data_anomalies_valid_status"
  end
end
