require "digest"
require "roo"

module BinImport
  class Importer
    def initialize(path, source_filename: nil)
      @path = path
      @source_filename = source_filename || File.basename(path)
      @workbook = Roo::Excelx.new(path)
    end

    def call
      Template.validate!(@workbook)
      checksum = Digest::SHA256.file(@path).hexdigest
      if ImportBatch.where(status: "validated").exists?(file_checksum: checksum)
        raise ArgumentError, "Arquivo já importado"
      end

      template = Template.register!(@workbook)
      rows = Template::SHEETS.to_h { |sheet| [ sheet, rows_for(sheet) ] }
      channel = resolve_channel!(rows.fetch("Mapa de Clientes BIN"))
      batch = ImportBatch.find_or_initialize_by(file_checksum: checksum)
      batch.assign_attributes(
        channel:, import_template: template, source_filename: @source_filename,
        source_file_date: source_file_date, status: "pending", validation_errors: []
      )
      batch.save!

      validation = Validator.new(rows).validate!
      validate_existing_establishments!(channel, rows)
      DailyRevenuePartitions.ensure!(validation.previous_period)
      DailyRevenuePartitions.ensure!(validation.current_period)
      batch.update!(
        previous_period: validation.previous_period, current_period: validation.current_period,
        covered_periods: validation.covered_periods.map(&:to_s),
        current_month_cutoff_day: Cutoff.day(rows.fetch("Faturamento"))
      )
      detect_short_cutoff!(batch)

      ApplicationRecord.transaction do
        persist_raw_rows(batch, rows)
        establishments = persist_map_rows(batch, rows.fetch("Mapa de Clientes BIN"))
        persist_revenue_rows(batch, rows.fetch("Faturamento"), establishments)
        persist_activation_rows(batch, rows.fetch("Ativacao"), establishments)
        consolidate!(batch)
        detect_anomalies!(batch)
        batch.update!(status: "validated")
      end
      refresh_views!(batch)
      batch
    rescue StandardError => e
      batch&.update(status: "failed", validation_errors: [ e.message ])
      raise
    end

    private

    # Aqui os dados já estão gravados e consolidados: só as views ficaram velhas. Marcar o
    # lote como falho faria o reenvio tentar apagá-lo com chaves apontando para ele.
    def refresh_views!(batch)
      AuditViews.refresh!
    rescue StandardError => e
      Rails.logger.error("[import #{batch.id}] views não atualizadas: #{e.class}: #{e.message}")
      batch.update!(validation_errors: [ "Views de auditoria não atualizadas: #{e.message}. Use Reprocessar lote." ])
    end

    def name_attributes(sheet_name, row)
      columns = Template.name_columns(sheet_name)
      { legal_name: row[columns[:legal_name]], trade_name: row[columns[:trade_name]] }
    end

    def rows_for(sheet_name)
      @workbook.default_sheet = sheet_name
      headers = @workbook.row(1).map(&:to_s)
      (2..@workbook.last_row).filter_map do |number|
        values = @workbook.row(number)
        next if values.compact.empty?

        headers.zip(values).to_h.merge("_row_number" => number)
      end
    end

    def resolve_channel!(map_rows)
      report_ids = map_rows.pluck("REPORT_ID").compact.map(&:to_s).uniq
      canals = map_rows.pluck("CANAL").compact.map(&:to_s).reject(&:blank?).uniq
      raise ArgumentError, "Arquivo deve conter exatamente um REPORT_ID" unless report_ids.one?
      raise ArgumentError, "Arquivo deve conter exatamente um CANAL" unless canals.one?

      ChannelResolver.call(report_id: report_ids.first, name: canals.first)
    end

    def source_file_date
      match = @source_filename.match(/_(\d{8})\.xlsx\z/i)
      Date.strptime(match[1], "%Y%m%d") if match
    end

    RAW_ROW_BATCH = 500

    # Em lotes para não materializar o payload de todas as linhas de uma aba de uma vez.
    def persist_raw_rows(batch, rows)
      now = Time.current
      rows.each do |sheet_name, sheet_rows|
        sheet_rows.each_slice(RAW_ROW_BATCH) do |slice|
          RawImportRow.insert_all!(slice.map do |row|
            {
              import_batch_id: batch.id, sheet_name:, row_number: row.fetch("_row_number"),
              payload: json_payload(row), created_at: now, updated_at: now
            }
          end)
        end
      end
    end

    def json_payload(row)
      row.except("_row_number").transform_values do |value|
        case value
        when Date, Time, DateTime then value.iso8601
        when BigDecimal then value.to_s("F")
        else value
        end
      end
    end

    def persist_map_rows(batch, rows)
      now = Time.current
      snapshot_rows = []
      monthly_volume_rows = []
      establishments = rows.to_h do |row|
        sub_channel = find_sub_channel(batch.channel, row["SUB-CANAL"])
        establishment = find_establishment(batch.channel, row)
        snapshot_rows << map_attributes(batch, sub_channel, establishment, row).merge(
          created_at: now, updated_at: now
        )
        monthly_volume_rows.concat(monthly_volume_rows(batch, establishment, row))
        [ establishment.ec, establishment ]
      end
      MapSnapshot.insert_all!(snapshot_rows)
      persist_actions(batch, rows)
      MonthlyVolume.insert_all!(monthly_volume_rows) if monthly_volume_rows.any?
      establishments
    end

    def find_sub_channel(channel, value)
      name = value.to_s.strip
      (@sub_channels ||= {})[name] ||= channel.sub_channels.find_or_create_by!(name: name)
    end

    def find_company(cnpj)
      (@companies ||= {})[cnpj] ||= Company.find_or_create_by!(cnpj:)
    end

    def find_establishment(channel, row)
      cnpj = Normalizer.cnpj(row["CNPJ"])
      raise ArgumentError, "CNPJ inválido" unless cnpj.match?(/\A\d{14}\z/)

      company = find_company(cnpj)
      ec = Normalizer.ec(row["EC"])
      (@establishments ||= {})[ec] ||= Establishment.find_or_create_by!(ec:) do |establishment|
        establishment.company = company
        establishment.channel = channel
      end
    end

    def map_attributes(batch, sub_channel, establishment, row)
      {
        import_batch_id: batch.id, channel_id: batch.channel_id,
        sub_channel_id: sub_channel.id, establishment_id: establishment.id,
        source_hierarchy: row["HIERARQUIA"], entity_type: row["TIPO DE PESSOA"],
        **name_attributes("Mapa de Clientes BIN", row),
        business_line: row["RAMO DE ATIVIDADE"], cnae_code: row["CÓDIGO DO CNAE"],
        cnae_description: row["DESCRIÇÃO DO CNAE"], contract_status: row["STATUS DO CONTRATO"],
        best_conversation_raw: row["MELHOR CONVERSA"], work_phone: Normalizer.digits(row["TELEFONE DO TRABALHO"]),
        street_address: row["ENDEREÇO"], cep: Normalizer.cep(row["CEP"]), city: row["CIDADE"], state: row["ESTADO"],
        contact_name_1: row["NOME CONTATO 1"], contact_name_2: row["NOME CONTATO 2"],
        pj_mais_island: Normalizer.boolean(row["Ilha PJ+"]),
        vip_boarding_date: Normalizer.datetime(row["vip_boarding_date"]),
        vip_entry_reason: row["motivo_entrada_vip"],
        presumed_segment: row["SEGMENTO PRESUMIDO"], performed_segment: row["SEGMENTO PERFORMADO"],
        reciprocity_status: row["STATUS DE RECIPROCIDADE"], revenue_drop_cluster: row["Cluster Queda Fat"],
        average_revenue_3m: Normalizer.decimal(row["FATURAMENTO MÉDIO ÚLTIMOS 3 MESES"]),
        peak_revenue: Normalizer.decimal(row["MAIOR FATURAMENTO"]),
        revenue_diff_m1_m2: Normalizer.decimal(row["Diferença Fat M-1 x M-2"]),
        revenue_diff_pct: Normalizer.decimal(row["Diferença Fat %"]),
        active_current_month: Normalizer.boolean(row["ATIVO NO MÊS ATUAL?"]),
        active_previous_month: Normalizer.boolean(row["ATIVO NO ULTIMO MÊS?"]),
        active_last_30_days: Normalizer.boolean(row["ATIVO NOS ÚLTIMOS 30 DIAS?"]),
        last_transaction_on: Normalizer.date(row["DATA DA ÚLT TRANSAÇÃO"]),
        accredited_on: Normalizer.date(row["DATA DE CREDENCIAMENTO"]),
        installed_on: Normalizer.date(row["DATA DE INSTALAÇÃO"]), activated_on: Normalizer.date(row["DATA DE ATIVAÇÃO"]),
        suspended_on: Normalizer.date(row["DATA DE SUSPENSÃO"]),
        last_app_access_at: Normalizer.datetime(row["ULTIMO ACESSO NO APP"]),
        financial_solutions: row["SOLUÇÕES FINANCEIRAS"],
        auto_advance_boarding_status: row["STATUS ANTECIP AUTO NO BOARDING"],
        auto_advance_boarding_status_2: row["STATUS ANTECIP AUTO NO BOARDING.1"],
        preapproved_volume: Normalizer.decimal(row["VOLUME_PRE_APROVADO"]),
        preapproved_term: Normalizer.integer(row["PRAZO_PRE_APROVADO"]),
        preapproved_rate: Normalizer.decimal(row["TAXA_PRE_APROVADA"]),
        preapproved_installment: Normalizer.decimal(row["PARCELA_PRE_APROVADA"]),
        has_payment_link: Normalizer.boolean(row["POSSUI LINK PGTO"]),
        tap_on_phone_count: Normalizer.integer(row["QTDE TAP ON PHONE"]),
        smart_pos_count: Normalizer.integer(row["QTDE SMART POS"]),
        other_pos_count: Normalizer.integer(row["QTDE DEMAIS POS"]),
        mps_count: Normalizer.integer(row["QTDE MPS"]), pin_count: Normalizer.integer(row["QTDE PIN"]),
        tef_count: Normalizer.integer(row["QTDE TEF"]),
        other_terminals_count: Normalizer.integer(row["QTDE OUTROS TERMINAIS"]),
        total_terminals_count: Normalizer.integer(row["QTDE TOTAL TERMINAIS"]),
        net_mdr: Normalizer.decimal(row["NET MDR"]),
        net_mdr_status: row["NET MDR"].to_s == "Inativo" ? "Inativo" : nil, weekly_schedule: row["agenda_semanal"]
      }
    end

    def persist_actions(batch, rows)
      specifications = rows.flat_map do |row|
        row["MELHOR CONVERSA"].to_s.split(">").map(&:strip).reject(&:blank?).each_with_index.map do |text, index|
          [ Normalizer.ec(row["EC"]), text, index + 1 ]
        end
      end
      return if specifications.empty?

      now = Time.current
      action_rows = specifications.map(&:second).uniq.map do |text|
        { text: text, created_at: now, updated_at: now }
      end
      ConversationAction.insert_all(action_rows, unique_by: "index_conversation_actions_on_text")
      actions = ConversationAction.where(text: specifications.map(&:second)).index_by(&:text)
      snapshots = MapSnapshot.where(import_batch: batch).includes(:establishment)
        .index_by { |snapshot| snapshot.establishment.ec }
      MapSnapshotAction.insert_all!(specifications.map do |ec, text, position|
        {
          map_snapshot_id: snapshots.fetch(ec).id,
          conversation_action_id: actions.fetch(text).id,
          position: position
        }
      end)
    end

    def monthly_volume_rows(batch, establishment, row)
      row.filter_map do |header, value|
        match = header.match(/\AVOLUME DE (FATURAMENTO TOTAL|FATURAMENTO CRÉDITO|FATURAMENTO DÉBITO|ANTECIPAÇÃO) (\d{6})\z/)
        next unless match && (amount = Normalizer.decimal(value))

        { import_batch_id: batch.id, channel_id: batch.channel_id, establishment_id: establishment.id,
          period: Date.strptime(match[2], "%Y%m"),
          metric: { "FATURAMENTO TOTAL" => "total", "FATURAMENTO CRÉDITO" => "credito", "FATURAMENTO DÉBITO" => "debito", "ANTECIPAÇÃO" => "antecipacao" }.fetch(match[1]),
          amount:, created_at: Time.current, updated_at: Time.current }
      end
    end

    def persist_revenue_rows(batch, rows, establishments)
      now = Time.current
      snapshot_rows = []
      daily_rows = []
      rows.each do |row|
        establishment = establishments.fetch(Normalizer.ec(row["EC"]))
        sub_channel = find_sub_channel(batch.channel, row["SUB-CANAL"])
        snapshot_rows << {
          import_batch_id: batch.id, channel_id: batch.channel_id,
          establishment_id: establishment.id, sub_channel_id: sub_channel.id,
          source_hierarchy: row["HIERARQUIA"], **name_attributes("Faturamento", row),
          contract_status: row["STATUS DO CONTRATO"],
          suspended_on: Normalizer.date(row["DATA DE SUSPENSÃO"]),
          last_transaction_on: Normalizer.date(row["DATA DA ÚLT TRANSAÇÃO"]),
          active_last_60_days: Normalizer.boolean(row["ATIVO NOS ÚLTIMOS 60 DIAS?"]),
          street_address: row["ENDEREÇO"], city: row["CIDADE"], state: row["ESTADO"],
          cep: Normalizer.cep(row["CEP"]), cep_raw: row["CEP"].to_s,
          work_phone: Normalizer.digits(row["TELEFONE DO TRABALHO"]),
          work_phone_raw: row["TELEFONE DO TRABALHO"].to_s,
          cnae_code: row["CNAE"], cnae_description: row["DESCRIÇÃO DO CNAE"],
          previous_month_total: Normalizer.decimal(row["fat_total_m1"]) || 0,
          current_month_total: Normalizer.decimal(row["FATURAMENTO TOTAL DESTE MÊS"]) || 0,
          created_at: now, updated_at: now
        }
        daily_rows.concat(daily_revenue_rows(batch, establishment, row))
      end
      RevenueSnapshot.insert_all!(snapshot_rows)
      DailyRevenue.insert_all!(daily_rows)
    end

    def daily_revenue_rows(batch, establishment, row)
      [ [ batch.previous_period, "_M_1", false ], [ batch.current_period, "", true ] ].flat_map do |period, suffix, provisional|
        (1..31).filter_map do |day|
          amount = Normalizer.decimal(row["DIA #{format('%02d', day)}#{suffix}"]) || 0
          { import_batch_id: batch.id, channel_id: batch.channel_id, establishment_id: establishment.id,
            period:, day:, amount:, provisional:, created_at: Time.current, updated_at: Time.current } if amount.nonzero?
        end
      end
    end

    def validate_existing_establishments!(channel, rows)
      IdentityGuard.assert_existing!(channel, rows)
    end

    def persist_activation_rows(batch, rows, establishments)
      now = Time.current
      activation_rows = rows.map do |row|
        establishment = establishments[Normalizer.ec(row["EC"])]
        company = find_company(Normalizer.cnpj(row["CNPJ"]))
        sub_channel = find_sub_channel(batch.channel, row["SUB-CANAL"])
        {
          import_batch_id: batch.id, channel_id: batch.channel_id,
          sub_channel_id: sub_channel.id, company_id: company.id,
          establishment_id: establishment&.id, proposal_number: row["NR DA PROPOSTA"].to_s,
          source_hierarchy: row["HIERARQUIA"], **name_attributes("Ativacao", row),
          proposal_status: row["STATUS DA PROPOSTA"],
          proposed_on: Normalizer.date(row["DATA DA PROPOSTA"]),
          affiliated_on: Normalizer.date(row["DATA DE AFILIAÇÃO"]),
          installed_on: Normalizer.date(row["DATA DE INSTALAÇÃO"]),
          activated_on: Normalizer.date(row["DATA DE ATIVAÇÃO"]),
          average_ticket: Normalizer.decimal(row["TICKET MÉDIO"]),
          forecast_annual_revenue: Normalizer.decimal(row["FATURAMENTO ANUAL PREVISTO"]),
          created_at: now, updated_at: now
        }
      end
      ActivationProposal.insert_all!(activation_rows)
    end

    def consolidate!(batch)
      BinImport::Consolidator.new(batch).call
    end

    # Os dias ainda não cobertos chegam como zero, então o corte observado pode ficar abaixo
    # do que o arquivo realmente cobre. Registra a divergência para o analista decidir pelo
    # Operations::AdjustCutoff — nunca estende a cobertura por conta própria.
    def detect_short_cutoff!(batch)
      file_date = batch.source_file_date
      return if file_date.blank? || batch.current_period.blank?
      return unless file_date.beginning_of_month == batch.current_period

      expected = file_date.day - 1
      return if expected <= batch.current_month_cutoff_day.to_i

      Anomalies.record!(
        batch:, type: "cutoff_below_file_date", severity: "info",
        details: { observed_cutoff: batch.current_month_cutoff_day, file_day: file_date.day,
                   expected_cutoff: expected }
      )
    end

    def detect_anomalies!(batch)
      BinImport::AnomalyDetector.new(batch).call
    end
  end
end
