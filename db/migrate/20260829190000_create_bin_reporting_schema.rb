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
      t.string :name, null: false, comment: "Origem: coluna \"CANAL\" da aba Mapa de Clientes BIN; Faturamento e Ativacao repetem a coluna"
      t.timestamps
    end
    add_index :channels, :uuid, unique: true
    add_index :channels, :external_id, unique: true
    add_index :channels, :name, using: :gin, opclass: :gin_trgm_ops

    create_table :sub_channels do |t|
      t.uuid :uuid, null: false, default: -> { 'gen_random_uuid()' }
      t.references :channel, null: false, foreign_key: true
      t.string :name, null: false, comment: "Origem: coluna \"SUB-CANAL\" das abas Mapa de Clientes BIN, Faturamento e Ativacao"
      t.timestamps
    end
    add_index :sub_channels, :uuid, unique: true
    add_index :sub_channels, %i[channel_id name], unique: true
    add_index :sub_channels, %i[id channel_id], unique: true
    add_index :sub_channels, :name, using: :gin, opclass: :gin_trgm_ops

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
      t.date :previous_period
      t.date :current_period
      t.jsonb :covered_periods, null: false, default: []
      t.integer :current_month_cutoff_day
      t.string :status, null: false, default: 'pending'
      t.jsonb :validation_errors, null: false, default: []
      t.timestamps
    end
    add_index :import_batches, :uuid, unique: true
    add_index :import_batches, :file_checksum, unique: true
    add_index :import_batches, %i[channel_id current_period]
    add_check_constraint :import_batches, "status IN ('pending', 'validated', 'failed', 'superseded')",
      name: 'import_batches_valid_status'
    add_check_constraint :import_batches, 'current_month_cutoff_day BETWEEN 1 AND 31',
      name: 'import_batches_valid_cutoff'

    create_table :revenue_snapshots do |t|
      t.references :import_batch, null: false, foreign_key: true
      t.references :channel, null: false, foreign_key: true
      t.references :establishment, null: false, foreign_key: true
      t.references :sub_channel, null: false, foreign_key: true
      t.string :source_hierarchy, comment: "Origem: coluna \"HIERARQUIA\" da aba Faturamento"
      # Nesta aba a Fiserv entrega os dois cabeçalhos trocados (ver Template::INVERTED_NAME_SHEETS).
      t.string :legal_name, comment: "Origem: coluna \"NOME FANTASIA\" da aba Faturamento (cabeçalho invertido na origem)"
      t.string :trade_name, comment: "Origem: coluna \"RAZÃO SOCIAL\" da aba Faturamento (cabeçalho invertido na origem)"
      t.string :contract_status, comment: "Origem: coluna \"STATUS DO CONTRATO\" da aba Faturamento"
      t.date :suspended_on, comment: "Origem: coluna \"DATA DE SUSPENSÃO\" da aba Faturamento"
      t.date :last_transaction_on, comment: "Origem: coluna \"DATA DA ÚLT TRANSAÇÃO\" da aba Faturamento"
      t.boolean :active_last_60_days, comment: "Origem: coluna \"ATIVO NOS ÚLTIMOS 60 DIAS?\" da aba Faturamento"
      t.string :street_address, comment: "Origem: coluna \"ENDEREÇO\" da aba Faturamento"
      t.string :cep, comment: "Origem: coluna \"CEP\" da aba Faturamento"
      t.string :cep_raw, comment: "Origem: coluna \"CEP\" da aba Faturamento"
      t.string :city, comment: "Origem: coluna \"CIDADE\" da aba Faturamento"
      t.string :state, comment: "Origem: coluna \"ESTADO\" da aba Faturamento"
      t.string :work_phone, comment: "Origem: coluna \"TELEFONE DO TRABALHO\" da aba Faturamento"
      t.string :work_phone_raw, comment: "Origem: coluna \"TELEFONE DO TRABALHO\" da aba Faturamento"
      t.string :cnae_code, comment: "Origem: coluna \"CNAE\" da aba Faturamento"
      t.string :cnae_description, comment: "Origem: coluna \"DESCRIÇÃO DO CNAE\" da aba Faturamento"
      t.decimal :previous_month_total, precision: 18, scale: 2, null: false, default: 0, comment: "Origem: coluna \"fat_total_m1\" da aba Faturamento"
      t.decimal :current_month_total, precision: 18, scale: 2, null: false, default: 0, comment: "Origem: coluna \"FATURAMENTO TOTAL DESTE MÊS\" da aba Faturamento"
      t.timestamps
    end
    add_index :revenue_snapshots, %i[import_batch_id establishment_id], unique: true
    add_index :revenue_snapshots, %i[channel_id sub_channel_id]

    create_table :map_snapshots do |t|
      t.references :import_batch, null: false, foreign_key: true
      t.references :channel, null: false, foreign_key: true
      t.references :establishment, null: false, foreign_key: true
      t.references :sub_channel, null: false, foreign_key: true
      t.string :source_hierarchy, comment: "Origem: coluna \"HIERARQUIA\" da aba Mapa de Clientes BIN"
      t.string :entity_type, comment: "Origem: coluna \"TIPO DE PESSOA\" da aba Mapa de Clientes BIN"
      t.string :legal_name, comment: "Origem: coluna \"RAZÃO SOCIAL\" da aba Mapa de Clientes BIN"
      t.string :trade_name, comment: "Origem: coluna \"NOME FANTASIA\" da aba Mapa de Clientes BIN"
      t.string :business_line, comment: "Origem: coluna \"RAMO DE ATIVIDADE\" da aba Mapa de Clientes BIN"
      t.string :cnae_code, comment: "Origem: coluna \"CÓDIGO DO CNAE\" da aba Mapa de Clientes BIN"
      t.string :cnae_description, comment: "Origem: coluna \"DESCRIÇÃO DO CNAE\" da aba Mapa de Clientes BIN"
      t.string :contract_status, comment: "Origem: coluna \"STATUS DO CONTRATO\" da aba Mapa de Clientes BIN"
      t.text :best_conversation_raw, comment: "Origem: coluna \"MELHOR CONVERSA\" da aba Mapa de Clientes BIN"
      t.string :work_phone, comment: "Origem: coluna \"TELEFONE DO TRABALHO\" da aba Mapa de Clientes BIN"
      t.string :street_address, comment: "Origem: coluna \"ENDEREÇO\" da aba Mapa de Clientes BIN"
      t.string :cep, comment: "Origem: coluna \"CEP\" da aba Mapa de Clientes BIN"
      t.string :contact_name_1, comment: "Origem: coluna \"NOME CONTATO 1\" da aba Mapa de Clientes BIN"
      t.string :contact_name_2, comment: "Origem: coluna \"NOME CONTATO 2\" da aba Mapa de Clientes BIN"
      t.string :city, comment: "Origem: coluna \"CIDADE\" da aba Mapa de Clientes BIN"
      t.string :state, comment: "Origem: coluna \"ESTADO\" da aba Mapa de Clientes BIN"
      t.boolean :pj_mais_island, comment: "Origem: coluna \"Ilha PJ+\" da aba Mapa de Clientes BIN"
      t.datetime :vip_boarding_date, comment: "Origem: coluna \"vip_boarding_date\" da aba Mapa de Clientes BIN"
      t.string :vip_entry_reason, comment: "Origem: coluna \"motivo_entrada_vip\" da aba Mapa de Clientes BIN"
      t.string :presumed_segment, comment: "Origem: coluna \"SEGMENTO PRESUMIDO\" da aba Mapa de Clientes BIN"
      t.string :performed_segment, comment: "Origem: coluna \"SEGMENTO PERFORMADO\" da aba Mapa de Clientes BIN"
      t.string :reciprocity_status, comment: "Origem: coluna \"STATUS DE RECIPROCIDADE\" da aba Mapa de Clientes BIN"
      t.decimal :average_revenue_3m, precision: 18, scale: 2, comment: "Origem: coluna \"FATURAMENTO MÉDIO ÚLTIMOS 3 MESES\" da aba Mapa de Clientes BIN"
      t.decimal :peak_revenue, precision: 18, scale: 2, comment: "Origem: coluna \"MAIOR FATURAMENTO\" da aba Mapa de Clientes BIN"
      t.decimal :revenue_diff_m1_m2, precision: 18, scale: 2, comment: "Origem: coluna \"Diferença Fat M-1 x M-2\" da aba Mapa de Clientes BIN"
      t.decimal :revenue_diff_pct, precision: 12, scale: 4, comment: "Origem: coluna \"Diferença Fat %\" da aba Mapa de Clientes BIN"
      t.string :revenue_drop_cluster, comment: "Origem: coluna \"Cluster Queda Fat\" da aba Mapa de Clientes BIN"
      t.boolean :active_current_month, comment: "Origem: coluna \"ATIVO NO MÊS ATUAL?\" da aba Mapa de Clientes BIN"
      t.boolean :active_previous_month, comment: "Origem: coluna \"ATIVO NO ULTIMO MÊS?\" da aba Mapa de Clientes BIN"
      t.boolean :active_last_30_days, comment: "Origem: coluna \"ATIVO NOS ÚLTIMOS 30 DIAS?\" da aba Mapa de Clientes BIN"
      t.date :last_transaction_on, comment: "Origem: coluna \"DATA DA ÚLT TRANSAÇÃO\" da aba Mapa de Clientes BIN"
      t.date :accredited_on, comment: "Origem: coluna \"DATA DE CREDENCIAMENTO\" da aba Mapa de Clientes BIN"
      t.date :installed_on, comment: "Origem: coluna \"DATA DE INSTALAÇÃO\" da aba Mapa de Clientes BIN"
      t.date :activated_on, comment: "Origem: coluna \"DATA DE ATIVAÇÃO\" da aba Mapa de Clientes BIN"
      t.date :suspended_on, comment: "Origem: coluna \"DATA DE SUSPENSÃO\" da aba Mapa de Clientes BIN"
      t.datetime :last_app_access_at, comment: "Origem: coluna \"ULTIMO ACESSO NO APP\" da aba Mapa de Clientes BIN"
      t.string :financial_solutions, comment: "Origem: coluna \"SOLUÇÕES FINANCEIRAS\" da aba Mapa de Clientes BIN"
      t.string :auto_advance_boarding_status, comment: "Origem: coluna \"STATUS ANTECIP AUTO NO BOARDING\" da aba Mapa de Clientes BIN"
      t.string :auto_advance_boarding_status_2, comment: "Origem: coluna \"STATUS ANTECIP AUTO NO BOARDING.1\" da aba Mapa de Clientes BIN"
      t.decimal :preapproved_volume, precision: 18, scale: 2, comment: "Origem: coluna \"VOLUME_PRE_APROVADO\" da aba Mapa de Clientes BIN"
      t.integer :preapproved_term, comment: "Origem: coluna \"PRAZO_PRE_APROVADO\" da aba Mapa de Clientes BIN"
      t.decimal :preapproved_rate, precision: 12, scale: 4, comment: "Origem: coluna \"TAXA_PRE_APROVADA\" da aba Mapa de Clientes BIN"
      t.decimal :preapproved_installment, precision: 18, scale: 2, comment: "Origem: coluna \"PARCELA_PRE_APROVADA\" da aba Mapa de Clientes BIN"
      t.boolean :has_payment_link, comment: "Origem: coluna \"POSSUI LINK PGTO\" da aba Mapa de Clientes BIN"
      # Contagem de terminais por tipo; todas vêm da aba Mapa de Clientes BIN.
      {
        tap_on_phone_count: "QTDE TAP ON PHONE", smart_pos_count: "QTDE SMART POS",
        other_pos_count: "QTDE DEMAIS POS", mps_count: "QTDE MPS", pin_count: "QTDE PIN",
        tef_count: "QTDE TEF", other_terminals_count: "QTDE OUTROS TERMINAIS",
        total_terminals_count: "QTDE TOTAL TERMINAIS"
      }.each do |column, header|
        t.integer column, comment: "Origem: coluna \"#{header}\" da aba Mapa de Clientes BIN"
      end
      t.decimal :net_mdr, precision: 12, scale: 4, comment: "Origem: coluna \"NET MDR\" da aba Mapa de Clientes BIN"
      t.string :net_mdr_status, comment: "Origem: coluna \"NET MDR\" da aba Mapa de Clientes BIN, só quando o valor é \"Inativo\""
      t.string :weekly_schedule, comment: "Origem: coluna \"agenda_semanal\" da aba Mapa de Clientes BIN"
      t.timestamps
    end
    add_index :map_snapshots, %i[import_batch_id establishment_id], unique: true
    add_index :map_snapshots, %i[channel_id sub_channel_id]
    %i[legal_name trade_name city].each { |column| add_index :map_snapshots, column, using: :gin, opclass: :gin_trgm_ops }

    create_table :activation_proposals do |t|
      t.references :import_batch, null: false, foreign_key: true
      t.references :channel, null: false, foreign_key: true
      t.references :sub_channel, null: false, foreign_key: true
      t.references :company, null: false, foreign_key: true
      t.references :establishment, foreign_key: true
      t.string :source_hierarchy, comment: "Origem: coluna \"HIERARQUIA\" da aba Ativacao"
      t.string :proposal_number, null: false, comment: "Origem: coluna \"NR DA PROPOSTA\" da aba Ativacao"
      # Nesta aba a Fiserv entrega os dois cabeçalhos trocados (ver Template::INVERTED_NAME_SHEETS).
      t.string :legal_name, comment: "Origem: coluna \"NOME FANTASIA\" da aba Ativacao (cabeçalho invertido na origem)"
      t.string :trade_name, comment: "Origem: coluna \"RAZÃO SOCIAL\" da aba Ativacao (cabeçalho invertido na origem)"
      t.string :proposal_status, comment: "Origem: coluna \"STATUS DA PROPOSTA\" da aba Ativacao"
      t.date :proposed_on, comment: "Origem: coluna \"DATA DA PROPOSTA\" da aba Ativacao"
      t.date :affiliated_on, comment: "Origem: coluna \"DATA DE AFILIAÇÃO\" da aba Ativacao"
      t.date :installed_on, comment: "Origem: coluna \"DATA DE INSTALAÇÃO\" da aba Ativacao"
      t.date :activated_on, comment: "Origem: coluna \"DATA DE ATIVAÇÃO\" da aba Ativacao"
      t.decimal :average_ticket, precision: 18, scale: 2, comment: "Origem: coluna \"TICKET MÉDIO\" da aba Ativacao"
      t.decimal :forecast_annual_revenue, precision: 18, scale: 2, comment: "Origem: coluna \"FATURAMENTO ANUAL PREVISTO\" da aba Ativacao"
      t.timestamps
    end
    add_index :activation_proposals, %i[import_batch_id proposal_number], unique: true
    add_index :activation_proposals, :proposal_number

    create_table :monthly_volumes do |t|
      t.references :import_batch, null: false, foreign_key: true
      t.references :channel, null: false, foreign_key: true
      t.references :establishment, null: false, foreign_key: true
      t.date :period, null: false
      t.string :metric, null: false
      t.decimal :amount, precision: 18, scale: 2, null: false
      t.timestamps
    end
    add_index :monthly_volumes, %i[import_batch_id establishment_id period metric], unique: true,
      name: 'index_monthly_volumes_on_batch_establishment_period_metric'
    add_index :monthly_volumes, %i[channel_id period]

    execute <<~SQL
      CREATE TABLE daily_revenues (
        id bigserial NOT NULL,
        import_batch_id bigint NOT NULL REFERENCES import_batches(id),
        channel_id bigint NOT NULL REFERENCES channels(id),
        establishment_id bigint NOT NULL REFERENCES establishments(id),
        period date NOT NULL,
        day integer NOT NULL,
        amount numeric(18,2) NOT NULL,
        provisional boolean NOT NULL,
        created_at timestamp(6) without time zone NOT NULL,
        updated_at timestamp(6) without time zone NOT NULL,
        CONSTRAINT daily_revenues_valid_day CHECK (day BETWEEN 1 AND 31)
      ) PARTITION BY RANGE (period);
      CREATE TABLE daily_revenues_default PARTITION OF daily_revenues DEFAULT;
    SQL
    add_index :daily_revenues, %i[import_batch_id establishment_id period day], unique: true,
      name: 'index_daily_revenues_unique_snapshot_day'
    add_index :daily_revenues, %i[channel_id period day]
    add_index :daily_revenues, :import_batch_id
    add_index :daily_revenues, :channel_id
    add_index :daily_revenues, :establishment_id

    create_table :daily_revenues_consolidated, id: false do |t|
      t.references :establishment, null: false, foreign_key: true
      t.references :channel, null: false, foreign_key: true
      t.date :period, null: false
      t.integer :day, null: false
      t.decimal :amount, precision: 18, scale: 2, null: false
      t.boolean :provisional, null: false
      t.references :source_import_batch, null: false, foreign_key: { to_table: :import_batches }
      t.integer :revised_count, null: false, default: 0
      t.timestamps
    end
    add_index :daily_revenues_consolidated, %i[establishment_id period day], unique: true,
      name: 'index_daily_revenues_consolidated_primary'
    add_index :daily_revenues_consolidated, %i[channel_id period day]

    create_table :monthly_volumes_consolidated, id: false do |t|
      t.references :channel, null: false, foreign_key: true
      t.references :establishment, null: false, foreign_key: true
      t.date :period, null: false
      t.string :metric, null: false
      t.decimal :amount, precision: 18, scale: 2, null: false
      t.references :source_import_batch, null: false, foreign_key: { to_table: :import_batches }
      t.timestamps
    end
    add_index :monthly_volumes_consolidated, %i[establishment_id period metric], unique: true,
      name: 'index_monthly_volumes_consolidated_primary'
    add_index :monthly_volumes_consolidated, %i[channel_id period]

    create_table :period_coverages, id: false do |t|
      t.references :channel, null: false, foreign_key: true
      t.date :period, null: false
      t.integer :max_known_day, null: false
      t.boolean :closed, null: false, default: false
      t.references :last_import_batch, null: false, foreign_key: { to_table: :import_batches }
      t.timestamps
    end
    add_index :period_coverages, %i[channel_id period], unique: true

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
      t.date :period, null: false
      t.integer :day, null: false
      t.decimal :previous_amount, precision: 18, scale: 2, null: false
      t.decimal :new_amount, precision: 18, scale: 2, null: false
      t.references :import_batch, null: false, foreign_key: true
      t.datetime :detected_at, null: false
    end

    create_table :conversation_actions do |t|
      t.string :text, null: false, comment: "Origem: coluna \"MELHOR CONVERSA\" da aba Mapa de Clientes BIN"
      t.timestamps
    end
    add_index :conversation_actions, :text, unique: true

    create_table :map_snapshot_actions do |t|
      t.references :map_snapshot, null: false, foreign_key: true
      t.references :conversation_action, null: false, foreign_key: true
      t.integer :position, null: false, comment: "Origem: coluna \"MELHOR CONVERSA\" da aba Mapa de Clientes BIN"
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
