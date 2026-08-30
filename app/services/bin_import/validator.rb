module BinImport
  class Validator
    attr_reader :previous_period, :current_period, :covered_periods

    def initialize(rows)
      @rows = rows
      @map_rows = rows.fetch("Mapa de Clientes BIN")
      @revenue_rows = rows.fetch("Faturamento")
    end

    def validate!
      validate_identity!
      derive_competencies!
      self
    end

    def validate_identity!
      validate_single_channel!
      validate_required_values!
      validate_ec_identity!
      validate_revenue_membership!
      validate_daily_totals!
      self
    end

    private

    def validate_single_channel!
      report_ids = values(@map_rows, "REPORT_ID")
      channels = @rows.values.flat_map { |sheet_rows| values(sheet_rows, "CANAL") }.uniq
      raise ArgumentError, "Arquivo deve conter exatamente um REPORT_ID" unless report_ids.one?
      raise ArgumentError, "Arquivo deve conter exatamente um CANAL" unless channels.one?
    end

    def validate_required_values!
      @rows.each do |sheet_name, sheet_rows|
        required = Template::REQUIRED_HEADERS.fetch(sheet_name)
        sheet_rows.each do |row|
          missing = required.select { |header| row[header].blank? }
          missing.delete("CANAL") if sheet_name == "Mapa de Clientes BIN"
          next if missing.empty?

          raise ArgumentError, "#{sheet_name} linha #{row['_row_number']}: campos obrigatórios vazios: #{missing.join(', ')}"
        end
      end
    end

    def validate_ec_identity!
      identities = Hash.new { |hash, key| hash[key] = [] }
      @rows.each_value do |sheet_rows|
        sheet_rows.each do |row|
          ec = Normalizer.ec(row["EC"])
          next if ec.blank?

          identities[ec] << Normalizer.cnpj(row["CNPJ"])
        end
      end
      changed = identities.find { |_ec, cnpjs| cnpjs.uniq.many? }
      raise ArgumentError, "EC #{changed.first} associado a mais de um CNPJ" if changed
    end

    def validate_revenue_membership!
      map_ecs = @map_rows.to_set { |row| Normalizer.ec(row["EC"]) }
      missing = @revenue_rows.filter_map do |row|
        ec = Normalizer.ec(row["EC"])
        ec unless map_ecs.include?(ec)
      end
      raise ArgumentError, "ECs de Faturamento ausentes no Mapa: #{missing.join(', ')}" if missing.any?
    end

    def validate_daily_totals!
      @revenue_rows.each do |row|
        validate_daily_series!(row, "_M_1", "fat_total_m1")
        validate_daily_series!(row, "", "FATURAMENTO TOTAL DESTE MÊS")
      end
    end

    def validate_daily_series!(row, suffix, total_header)
      total = Normalizer.decimal(row[total_header]) || 0
      sum = (1..31).sum { |day| Normalizer.decimal(row[format("DIA %02d%s", day, suffix)]) || 0 }
      return if sum == total

      raise ArgumentError, "Faturamento linha #{row['_row_number']}: dias não reconciliam com #{total_header}"
    end

    def derive_competencies!
      @covered_periods = Template::VOLUME_MONTHS.map { |month| Date.strptime(month, "%Y%m") }
      map_by_ec = @map_rows.index_by { |row| Normalizer.ec(row["EC"]) }
      @previous_period = matching_period(map_by_ec, "fat_total_m1")
      @current_period = matching_period(map_by_ec, "FATURAMENTO TOTAL DESTE MÊS")
      return if @current_period == @previous_period.next_month

      raise ArgumentError, "Competências reconciliadas não são consecutivas"
    end

    def matching_period(map_by_ec, revenue_header)
      scores = @covered_periods.to_h do |period|
        volume_header = "VOLUME DE FATURAMENTO TOTAL #{period.strftime('%Y%m')}"
        score = @revenue_rows.count do |row|
          map_value = map_by_ec[Normalizer.ec(row["EC"])]&.fetch(volume_header, nil)
          map_value.present? && Normalizer.decimal(map_value) == (Normalizer.decimal(row[revenue_header]) || 0)
        end
        [ period, score ]
      end
      best = scores.max_by { |_period, score| score }
      raise ArgumentError, "Não foi possível reconciliar #{revenue_header} com os volumes mensais" if best.last.zero?
      raise ArgumentError, "Reconciliação ambígua para #{revenue_header}" if scores.values.count(best.last) > 1

      best.first
    end

    def values(rows, header)
      rows.filter_map { |row| row[header].to_s.strip.presence }.uniq
    end
  end
end
