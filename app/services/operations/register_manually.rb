require "digest"

module Operations
  class RegisterManually
    NAME = "cadastrar_manualmente"

    def self.call(attrs)
      new(attrs).call
    end

    def initialize(attrs)
      @attrs = attrs.to_h.stringify_keys
    end

    def call
      assert_identifiers!
      validate_competencies!
      rows = sheet_rows
      BinImport::Validator.new(rows).validate_identity!
      channel = BinImport::ChannelResolver.call(report_id:, canal:)
      BinImport::IdentityGuard.assert_existing!(channel, rows)

      batch = nil
      ApplicationRecord.transaction do
        template = BinImport::Template.register!
        batch = ImportBatch.create!(
          channel:, import_template: template, source_filename: "manual",
          file_checksum: checksum, competencia_m1:, competencia_atual:,
          dia_corte_mes_atual: cutoff_day, status: "pending"
        )
        persist!(batch, channel, rows)
        if revenue_row.present?
          DailyRevenuePartitions.ensure!(competencia_m1)
          DailyRevenuePartitions.ensure!(competencia_atual)
          BinImport::Consolidator.new(batch).call
        end
        batch.update!(status: "validated")
        AuditViews.refresh!
      end
      batch
    rescue StandardError => error
      batch&.update(status: "failed", validation_errors: [ error.message ])
      raise
    end

    private

    def assert_identifiers!
      ec = BinImport::Normalizer.digits(@attrs.fetch("ec"))
      cnpj = BinImport::Normalizer.digits(@attrs.fetch("cnpj"))
      raise ArgumentError, "EC inválido" unless ec.match?(/\A\d{8}\z/)
      raise ArgumentError, "CNPJ inválido" unless cnpj.match?(/\A\d{14}\z/)
    end

    def validate_competencies!
      return unless revenue_requested?
      if competencia_m1.blank? || competencia_atual.blank?
        raise ArgumentError, "Competências são obrigatórias no cadastro com faturamento"
      end
      return if competencia_atual == competencia_m1.next_month

      raise ArgumentError, "Competências devem ser meses consecutivos"
    end

    def sheet_rows
      {
        "Mapa de Clientes BIN" => [ map_row ],
        "Faturamento" => [ revenue_row ].compact,
        "Ativacao" => []
      }
    end

    def map_row
      {
        "_row_number" => 2, "REPORT_ID" => report_id, "CANAL" => canal, "SUB-CANAL" => sub_canal,
        "EC" => @attrs.fetch("ec"), "CNPJ" => @attrs.fetch("cnpj"),
        "STATUS DO CONTRATO" => @attrs.fetch("status_contrato"),
        "NOME FANTASIA" => @attrs["razao_social"], "RAZÃO SOCIAL" => @attrs["nome_fantasia"],
        "TIPO DE PESSOA" => @attrs["tipo_pessoa"], "RAMO DE ATIVIDADE" => @attrs["ramo_atividade"],
        "CÓDIGO DO CNAE" => @attrs["cnae_codigo"], "DESCRIÇÃO DO CNAE" => @attrs["cnae_descricao"],
        "ENDEREÇO" => @attrs["endereco"], "CEP" => @attrs["cep"],
        "CIDADE" => @attrs["cidade"], "ESTADO" => @attrs["estado"],
        "TELEFONE DO TRABALHO" => @attrs["telefone_trabalho"],
        "NOME CONTATO 1" => @attrs["nome_contato_1"], "NOME CONTATO 2" => @attrs["nome_contato_2"],
        "SEGMENTO PRESUMIDO" => @attrs["segmento_presumido"],
        "SEGMENTO PERFORMADO" => @attrs["segmento_performado"],
        "HIERARQUIA" => canal
      }
    end

    def revenue_row
      return unless revenue_requested?

      row = map_row.merge(
        "fat_total_m1" => @attrs["fat_total_m1"],
        "FATURAMENTO TOTAL DESTE MÊS" => @attrs["fat_total_mes_atual"],
        "CNAE" => @attrs["cnae"]
      )
      (1..31).each do |day|
        row[format("DIA %02d_M_1", day)] = @attrs[format("dia_%02d_m1", day)]
        row[format("DIA %02d", day)] = @attrs[format("dia_%02d", day)]
      end
      row
    end

    def persist!(batch, channel, rows)
      map = rows.fetch("Mapa de Clientes BIN").first
      sub_channel = channel.sub_channels.find_or_create_by!(sub_canal: sub_canal)
      company = Company.find_or_create_by!(cnpj: BinImport::Normalizer.digits(map["CNPJ"]))
      establishment = Establishment.find_or_create_by!(ec: BinImport::Normalizer.digits(map["EC"])) do |record|
        record.company = company
        record.channel = channel
      end
      MapSnapshot.create!(
        import_batch: batch, channel:, sub_channel:, establishment:,
        hierarquia_origem: canal, status_contrato: map["STATUS DO CONTRATO"],
        razao_social: map["NOME FANTASIA"], nome_fantasia: map["RAZÃO SOCIAL"],
        tipo_pessoa: map["TIPO DE PESSOA"], ramo_atividade: map["RAMO DE ATIVIDADE"],
        cnae_codigo: map["CÓDIGO DO CNAE"], cnae_descricao: map["DESCRIÇÃO DO CNAE"],
        endereco: map["ENDEREÇO"], cep: BinImport::Normalizer.digits(map["CEP"]),
        cidade: map["CIDADE"], estado: map["ESTADO"],
        telefone_trabalho: BinImport::Normalizer.digits(map["TELEFONE DO TRABALHO"]),
        nome_contato_1: map["NOME CONTATO 1"], nome_contato_2: map["NOME CONTATO 2"],
        segmento_presumido: map["SEGMENTO PRESUMIDO"],
        segmento_performado: map["SEGMENTO PERFORMADO"]
      )
      return if rows.fetch("Faturamento").empty?

      revenue = rows.fetch("Faturamento").first
      RevenueSnapshot.create!(
        import_batch: batch, channel:, establishment:, sub_channel:,
        hierarquia_origem: canal, status_contrato: map["STATUS DO CONTRATO"],
        razao_social: @attrs["razao_social"], nome_fantasia: @attrs["nome_fantasia"],
        fat_total_m1: BinImport::Normalizer.decimal(revenue["fat_total_m1"]) || 0,
        fat_total_mes_atual: BinImport::Normalizer.decimal(revenue["FATURAMENTO TOTAL DESTE MÊS"]) || 0
      )
      daily = daily_rows(batch, establishment, revenue)
      DailyRevenue.insert_all!(daily) if daily.any?
    end

    def daily_rows(batch, establishment, row)
      [ [ competencia_m1, "_M_1", false ], [ competencia_atual, "", true ] ].flat_map do |competencia, suffix, provisional|
        (1..31).filter_map do |day|
          amount = BinImport::Normalizer.decimal(row[format("DIA %02d%s", day, suffix)]) || 0
          next unless amount.nonzero?

          {
            import_batch_id: batch.id, channel_id: batch.channel_id, establishment_id: establishment.id,
            competencia:, day:, amount:, provisional:, created_at: Time.current, updated_at: Time.current
          }
        end
      end
    end

    def report_id
      @attrs.fetch("report_id").to_s.strip
    end

    def canal
      @attrs.fetch("canal").to_s.strip
    end

    def sub_canal
      @attrs.fetch("sub_canal").to_s.strip
    end

    def competencia_m1
      parse_date(@attrs["competencia_m1"])
    end

    def competencia_atual
      parse_date(@attrs["competencia_atual"])
    end

    def cutoff_day
      return unless revenue_requested?

      BinImport::Cutoff.day([ revenue_row ])
    end

    def revenue_requested?
      money?("fat_total_m1") || money?("fat_total_mes_atual") ||
        (1..31).any? { |day| money?(format("dia_%02d", day)) || money?(format("dia_%02d_m1", day)) }
    end

    def money?(key)
      (BinImport::Normalizer.decimal(@attrs[key]) || 0).nonzero?
    end

    def checksum
      Digest::SHA256.hexdigest(sheet_rows.to_json)
    end

    def parse_date(value)
      return if value.blank?
      return value.to_date if value.respond_to?(:to_date)

      Date.iso8601(value.to_s)
    end
  end
end
