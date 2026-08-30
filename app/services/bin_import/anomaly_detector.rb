module BinImport
  class AnomalyDetector
    def initialize(batch)
      @batch = batch
    end

    def call
      detect_rows_without_channel!
      detect_duplicate_candidates!
      detect_companies_in_multiple_sub_channels!
      detect_changed_sub_channels!
    end

    private

    def detect_rows_without_channel!
      RawImportRow.where(import_batch: @batch, sheet_name: "Mapa de Clientes BIN").find_each do |row|
        next if row.payload["CANAL"].present?

        Anomalies.record!(
          batch: @batch, type: "row_without_canal", severity: "atencao",
          details: { sheet: row.sheet_name, row_number: row.row_number }
        )
      end
    end

    def detect_duplicate_candidates!
      candidates = snapshots.includes(establishment: :company).select do |snapshot|
        snapshot.establishment.ec.start_with?("3")
      end
      return if candidates.empty?

      pairs = candidates.to_h { |snapshot| [ snapshot, paired_ec(snapshot) ] }
      existing = Establishment.where(ec: pairs.values).pluck(:ec, :company_id).to_set
      pairs.each do |snapshot, paired_ec|
        establishment = snapshot.establishment
        next unless existing.include?([ paired_ec, establishment.company_id ])

        Anomalies.record!(
          batch: @batch, type: "ec_duplicate_candidate", severity: "atencao",
          company: establishment.company, establishment:,
          details: { paired_ec: }
        )
      end
    end

    def paired_ec(snapshot)
      "9#{snapshot.establishment.ec[1..]}"
    end

    def detect_companies_in_multiple_sub_channels!
      snapshots.joins(establishment: :company).group("companies.id")
        .having("COUNT(DISTINCT sub_channel_id) > 1").pluck("companies.id").each do |company_id|
        company = Company.find(company_id)
        sub_channels = snapshots.joins(:establishment)
          .where(establishments: { company_id: }).joins(:sub_channel)
          .distinct.order("sub_channels.sub_canal").pluck("sub_channels.sub_canal")
        Anomalies.record!(
          batch: @batch, type: "company_in_multiple_sub_channels", severity: "atencao",
          company:, details: { sub_channels: }
        )
      end
    end

    def detect_changed_sub_channels!
      current = snapshots.includes(:establishment, :sub_channel).to_a
      # ordem crescente + index_by mantém o snapshot mais recente de cada estabelecimento
      previous_by_establishment = MapSnapshot.where(establishment_id: current.map(&:establishment_id))
        .where.not(import_batch: @batch).order(:id).includes(:sub_channel)
        .index_by(&:establishment_id)

      current.each do |snapshot|
        previous = previous_by_establishment[snapshot.establishment_id]
        next unless previous && previous.sub_channel_id != snapshot.sub_channel_id

        Anomalies.record!(
          batch: @batch, type: "ec_changed_sub_channel", severity: "info",
          company: snapshot.establishment.company, establishment: snapshot.establishment,
          details: { previous: previous.sub_channel.sub_canal, current: snapshot.sub_channel.sub_canal }
        )
      end
    end

    def snapshots
      @snapshots ||= MapSnapshot.where(import_batch: @batch)
    end
  end
end
