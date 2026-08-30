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
      DailyRevenuePartitions.ensure!(validation.competencia_m1)
      DailyRevenuePartitions.ensure!(validation.competencia_atual)
      batch.update!(
        competencia_m1: validation.competencia_m1, competencia_atual: validation.competencia_atual,
        competencias_cobertas: validation.competencias_cobertas.map(&:to_s),
        dia_corte_mes_atual: Cutoff.day(rows.fetch("Faturamento"))
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
      AuditViews.refresh!
      batch
    rescue StandardError => e
      batch&.update(status: "failed", validation_errors: [ e.message ])
      raise
    end

    private

    def name_attributes(sheet_name, row)
      columns = Template.name_columns(sheet_name)
      { razao_social: row[columns[:razao_social]], nome_fantasia: row[columns[:nome_fantasia]] }
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

      ChannelResolver.call(report_id: report_ids.first, canal: canals.first)
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
      (@sub_channels ||= {})[name] ||= channel.sub_channels.find_or_create_by!(sub_canal: name)
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
        hierarquia_origem: row["HIERARQUIA"], tipo_pessoa: row["TIPO DE PESSOA"],
        **name_attributes("Mapa de Clientes BIN", row),
        ramo_atividade: row["RAMO DE ATIVIDADE"], cnae_codigo: row["CÓDIGO DO CNAE"],
        cnae_descricao: row["DESCRIÇÃO DO CNAE"], status_contrato: row["STATUS DO CONTRATO"],
        melhor_conversa_raw: row["MELHOR CONVERSA"], telefone_trabalho: Normalizer.digits(row["TELEFONE DO TRABALHO"]),
        endereco: row["ENDEREÇO"], cep: Normalizer.cep(row["CEP"]), cidade: row["CIDADE"], estado: row["ESTADO"],
        nome_contato_1: row["NOME CONTATO 1"], nome_contato_2: row["NOME CONTATO 2"],
        ilha_pj_mais: Normalizer.boolean(row["Ilha PJ+"]),
        vip_boarding_date: Normalizer.datetime(row["vip_boarding_date"]),
        motivo_entrada_vip: row["motivo_entrada_vip"],
        segmento_presumido: row["SEGMENTO PRESUMIDO"], segmento_performado: row["SEGMENTO PERFORMADO"],
        status_reciprocidade: row["STATUS DE RECIPROCIDADE"], cluster_queda_fat: row["Cluster Queda Fat"],
        faturamento_medio_3m: Normalizer.decimal(row["FATURAMENTO MÉDIO ÚLTIMOS 3 MESES"]),
        maior_faturamento: Normalizer.decimal(row["MAIOR FATURAMENTO"]),
        diferenca_fat_m1_m2: Normalizer.decimal(row["Diferença Fat M-1 x M-2"]),
        diferenca_fat_pct: Normalizer.decimal(row["Diferença Fat %"]),
        ativo_mes_atual: Normalizer.boolean(row["ATIVO NO MÊS ATUAL?"]),
        ativo_ultimo_mes: Normalizer.boolean(row["ATIVO NO ULTIMO MÊS?"]),
        ativo_ultimos_30_dias: Normalizer.boolean(row["ATIVO NOS ÚLTIMOS 30 DIAS?"]),
        data_ult_transacao: Normalizer.date(row["DATA DA ÚLT TRANSAÇÃO"]),
        data_credenciamento: Normalizer.date(row["DATA DE CREDENCIAMENTO"]),
        data_instalacao: Normalizer.date(row["DATA DE INSTALAÇÃO"]), data_ativacao: Normalizer.date(row["DATA DE ATIVAÇÃO"]),
        data_suspensao: Normalizer.date(row["DATA DE SUSPENSÃO"]),
        ultimo_acesso_app: Normalizer.datetime(row["ULTIMO ACESSO NO APP"]),
        solucoes_financeiras: row["SOLUÇÕES FINANCEIRAS"],
        status_antecip_auto_boarding: row["STATUS ANTECIP AUTO NO BOARDING"],
        status_antecip_auto_boarding_2: row["STATUS ANTECIP AUTO NO BOARDING.1"],
        volume_pre_aprovado: Normalizer.decimal(row["VOLUME_PRE_APROVADO"]),
        prazo_pre_aprovado: Normalizer.integer(row["PRAZO_PRE_APROVADO"]),
        taxa_pre_aprovada: Normalizer.decimal(row["TAXA_PRE_APROVADA"]),
        parcela_pre_aprovada: Normalizer.decimal(row["PARCELA_PRE_APROVADA"]),
        possui_link_pgto: Normalizer.boolean(row["POSSUI LINK PGTO"]),
        qtde_tap_on_phone: Normalizer.integer(row["QTDE TAP ON PHONE"]),
        qtde_smart_pos: Normalizer.integer(row["QTDE SMART POS"]),
        qtde_demais_pos: Normalizer.integer(row["QTDE DEMAIS POS"]),
        qtde_mps: Normalizer.integer(row["QTDE MPS"]), qtde_pin: Normalizer.integer(row["QTDE PIN"]),
        qtde_tef: Normalizer.integer(row["QTDE TEF"]),
        qtde_outros_terminais: Normalizer.integer(row["QTDE OUTROS TERMINAIS"]),
        qtde_total_terminais: Normalizer.integer(row["QTDE TOTAL TERMINAIS"]),
        net_mdr: Normalizer.decimal(row["NET MDR"]),
        net_mdr_status: row["NET MDR"].to_s == "Inativo" ? "Inativo" : nil, agenda_semanal: row["agenda_semanal"]
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
        { texto: text, created_at: now, updated_at: now }
      end
      ConversationAction.insert_all(action_rows, unique_by: "index_conversation_actions_on_texto")
      actions = ConversationAction.where(texto: specifications.map(&:second)).index_by(&:texto)
      snapshots = MapSnapshot.where(import_batch: batch).includes(:establishment)
        .index_by { |snapshot| snapshot.establishment.ec }
      MapSnapshotAction.insert_all!(specifications.map do |ec, text, position|
        {
          map_snapshot_id: snapshots.fetch(ec).id,
          conversation_action_id: actions.fetch(text).id,
          posicao: position
        }
      end)
    end

    def monthly_volume_rows(batch, establishment, row)
      row.filter_map do |header, value|
        match = header.match(/\AVOLUME DE (FATURAMENTO TOTAL|FATURAMENTO CRÉDITO|FATURAMENTO DÉBITO|ANTECIPAÇÃO) (\d{6})\z/)
        next unless match && (amount = Normalizer.decimal(value))

        { import_batch_id: batch.id, channel_id: batch.channel_id, establishment_id: establishment.id,
          competencia: Date.strptime(match[2], "%Y%m"),
          metrica: { "FATURAMENTO TOTAL" => "total", "FATURAMENTO CRÉDITO" => "credito", "FATURAMENTO DÉBITO" => "debito", "ANTECIPAÇÃO" => "antecipacao" }.fetch(match[1]),
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
          hierarquia_origem: row["HIERARQUIA"], **name_attributes("Faturamento", row),
          status_contrato: row["STATUS DO CONTRATO"],
          data_suspensao: Normalizer.date(row["DATA DE SUSPENSÃO"]),
          data_ult_transacao: Normalizer.date(row["DATA DA ÚLT TRANSAÇÃO"]),
          ativo_ultimos_60_dias: Normalizer.boolean(row["ATIVO NOS ÚLTIMOS 60 DIAS?"]),
          endereco: row["ENDEREÇO"], cidade: row["CIDADE"], estado: row["ESTADO"],
          cep: Normalizer.cep(row["CEP"]), cep_raw: row["CEP"].to_s,
          telefone_trabalho: Normalizer.digits(row["TELEFONE DO TRABALHO"]),
          telefone_raw: row["TELEFONE DO TRABALHO"].to_s,
          cnae_codigo: row["CNAE"], cnae_descricao: row["DESCRIÇÃO DO CNAE"],
          fat_total_m1: Normalizer.decimal(row["fat_total_m1"]) || 0,
          fat_total_mes_atual: Normalizer.decimal(row["FATURAMENTO TOTAL DESTE MÊS"]) || 0,
          created_at: now, updated_at: now
        }
        daily_rows.concat(daily_revenue_rows(batch, establishment, row))
      end
      RevenueSnapshot.insert_all!(snapshot_rows)
      DailyRevenue.insert_all!(daily_rows)
    end

    def daily_revenue_rows(batch, establishment, row)
      [ [ batch.competencia_m1, "_M_1", false ], [ batch.competencia_atual, "", true ] ].flat_map do |competencia, suffix, provisional|
        (1..31).filter_map do |day|
          amount = Normalizer.decimal(row["DIA #{format('%02d', day)}#{suffix}"]) || 0
          { import_batch_id: batch.id, channel_id: batch.channel_id, establishment_id: establishment.id,
            competencia:, day:, amount:, provisional:, created_at: Time.current, updated_at: Time.current } if amount.nonzero?
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
          establishment_id: establishment&.id, nr_da_proposta: row["NR DA PROPOSTA"].to_s,
          hierarquia_origem: row["HIERARQUIA"], **name_attributes("Ativacao", row),
          status_proposta: row["STATUS DA PROPOSTA"],
          data_proposta: Normalizer.date(row["DATA DA PROPOSTA"]),
          data_afiliacao: Normalizer.date(row["DATA DE AFILIAÇÃO"]),
          data_instalacao: Normalizer.date(row["DATA DE INSTALAÇÃO"]),
          data_ativacao: Normalizer.date(row["DATA DE ATIVAÇÃO"]),
          ticket_medio: Normalizer.decimal(row["TICKET MÉDIO"]),
          faturamento_anual_previsto: Normalizer.decimal(row["FATURAMENTO ANUAL PREVISTO"]),
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
      return if file_date.blank? || batch.competencia_atual.blank?
      return unless file_date.beginning_of_month == batch.competencia_atual

      expected = file_date.day - 1
      return if expected <= batch.dia_corte_mes_atual.to_i

      Anomalies.record!(
        batch:, type: "cutoff_below_file_date", severity: "info",
        details: { corte_observado: batch.dia_corte_mes_atual, dia_do_arquivo: file_date.day,
                   corte_esperado: expected }
      )
    end

    def detect_anomalies!(batch)
      BinImport::AnomalyDetector.new(batch).call
    end
  end
end
