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
      channel = BinImport::ChannelResolver.call(report_id:, name: channel_name)
      BinImport::IdentityGuard.assert_existing!(channel, rows)

      batch = nil
      ApplicationRecord.transaction do
        template = BinImport::Template.register!
        batch = ImportBatch.create!(
          channel:, import_template: template, source_filename: "manual",
          file_checksum: checksum, previous_period:, current_period:,
          current_month_cutoff_day: cutoff_day, status: "pending"
        )
        # As partições precisam existir antes do insert: linha que cai na partição
        # default impede a criação da partição do mês depois.
        if revenue_row.present?
          DailyRevenuePartitions.ensure!(previous_period)
          DailyRevenuePartitions.ensure!(current_period)
        end
        persist!(batch, channel, rows)
        BinImport::Consolidator.new(batch).call if revenue_row.present?
        batch.update!(status: "validated")
      end
      AuditViews.refresh!
      batch
    rescue StandardError => error
      batch&.update(status: "failed", validation_errors: [ error.message ])
      raise
    end

    private

    def assert_identifiers!
      ec = BinImport::Normalizer.ec(@attrs.fetch("ec"))
      cnpj = BinImport::Normalizer.cnpj(@attrs.fetch("cnpj"))
      raise ArgumentError, "EC inválido" unless ec.match?(/\A\d{8}\z/)
      raise ArgumentError, "CNPJ inválido" unless cnpj.match?(/\A\d{14}\z/)
    end

    def validate_competencies!
      return unless revenue_requested?
      if previous_period.blank? || current_period.blank?
        raise ArgumentError, "Competências são obrigatórias no cadastro com faturamento"
      end
      return if current_period == previous_period.next_month

      raise ArgumentError, "Competências devem ser meses consecutivos"
    end

    def sheet_rows
      {
        "Mapa de Clientes BIN" => [ map_row ],
        "Faturamento" => [ revenue_row ].compact,
        "Ativacao" => []
      }
    end

    # Cada aba tem sua própria convenção de cabeçalho para os nomes (ver Template).
    def name_headers(sheet_name)
      columns = BinImport::Template.name_columns(sheet_name)
      { columns[:legal_name] => @attrs["legal_name"], columns[:trade_name] => @attrs["trade_name"] }
    end

    def map_row
      {
        "_row_number" => 2, "REPORT_ID" => report_id, "CANAL" => channel_name, "SUB-CANAL" => sub_channel_name,
        "EC" => @attrs.fetch("ec"), "CNPJ" => @attrs.fetch("cnpj"),
        "STATUS DO CONTRATO" => @attrs.fetch("contract_status"),
        **name_headers("Mapa de Clientes BIN"),
        "TIPO DE PESSOA" => @attrs["entity_type"], "RAMO DE ATIVIDADE" => @attrs["business_line"],
        "CÓDIGO DO CNAE" => @attrs["cnae_code"], "DESCRIÇÃO DO CNAE" => @attrs["cnae_description"],
        "ENDEREÇO" => @attrs["street_address"], "CEP" => @attrs["cep"],
        "CIDADE" => @attrs["city"], "ESTADO" => @attrs["state"],
        "TELEFONE DO TRABALHO" => @attrs["work_phone"],
        "NOME CONTATO 1" => @attrs["contact_name_1"], "NOME CONTATO 2" => @attrs["contact_name_2"],
        "SEGMENTO PRESUMIDO" => @attrs["presumed_segment"],
        "SEGMENTO PERFORMADO" => @attrs["performed_segment"],
        "HIERARQUIA" => channel_name
      }
    end

    def revenue_row
      return unless revenue_requested?

      row = map_row.merge(
        **name_headers("Faturamento"),
        "fat_total_m1" => @attrs["previous_month_total"],
        "FATURAMENTO TOTAL DESTE MÊS" => @attrs["current_month_total"],
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
      sub_channel = channel.sub_channels.find_or_create_by!(name: sub_channel_name)
      company = Company.find_or_create_by!(cnpj: BinImport::Normalizer.cnpj(map["CNPJ"]))
      establishment = Establishment.find_or_create_by!(ec: BinImport::Normalizer.ec(map["EC"])) do |record|
        record.company = company
        record.channel = channel
      end
      MapSnapshot.create!(
        import_batch: batch, channel:, sub_channel:, establishment:,
        source_hierarchy: channel_name, contract_status: map["STATUS DO CONTRATO"],
        legal_name: @attrs["legal_name"], trade_name: @attrs["trade_name"],
        entity_type: map["TIPO DE PESSOA"], business_line: map["RAMO DE ATIVIDADE"],
        cnae_code: map["CÓDIGO DO CNAE"], cnae_description: map["DESCRIÇÃO DO CNAE"],
        street_address: map["ENDEREÇO"], cep: BinImport::Normalizer.cep(map["CEP"]),
        city: map["CIDADE"], state: map["ESTADO"],
        work_phone: BinImport::Normalizer.digits(map["TELEFONE DO TRABALHO"]),
        contact_name_1: map["NOME CONTATO 1"], contact_name_2: map["NOME CONTATO 2"],
        presumed_segment: map["SEGMENTO PRESUMIDO"],
        performed_segment: map["SEGMENTO PERFORMADO"]
      )
      return if rows.fetch("Faturamento").empty?

      revenue = rows.fetch("Faturamento").first
      RevenueSnapshot.create!(
        import_batch: batch, channel:, establishment:, sub_channel:,
        source_hierarchy: channel_name, contract_status: map["STATUS DO CONTRATO"],
        legal_name: @attrs["legal_name"], trade_name: @attrs["trade_name"],
        previous_month_total: BinImport::Normalizer.decimal(revenue["fat_total_m1"]) || 0,
        current_month_total: BinImport::Normalizer.decimal(revenue["FATURAMENTO TOTAL DESTE MÊS"]) || 0
      )
      daily = daily_rows(batch, establishment, revenue)
      DailyRevenue.insert_all!(daily) if daily.any?
    end

    def daily_rows(batch, establishment, row)
      [ [ previous_period, "_M_1", false ], [ current_period, "", true ] ].flat_map do |period, suffix, provisional|
        (1..31).filter_map do |day|
          amount = BinImport::Normalizer.decimal(row[format("DIA %02d%s", day, suffix)]) || 0
          next unless amount.nonzero?

          {
            import_batch_id: batch.id, channel_id: batch.channel_id, establishment_id: establishment.id,
            period:, day:, amount:, provisional:, created_at: Time.current, updated_at: Time.current
          }
        end
      end
    end

    def report_id
      @attrs.fetch("report_id").to_s.strip
    end

    def channel_name
      @attrs.fetch("channel_name").to_s.strip
    end

    def sub_channel_name
      @attrs.fetch("sub_channel_name").to_s.strip
    end

    def previous_period
      parse_date(@attrs["previous_period"])
    end

    def current_period
      parse_date(@attrs["current_period"])
    end

    def cutoff_day
      return unless revenue_requested?

      BinImport::Cutoff.day([ revenue_row ])
    end

    def revenue_requested?
      money?("previous_month_total") || money?("current_month_total") ||
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
