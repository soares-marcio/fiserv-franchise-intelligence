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
      snapshots.includes(establishment: :company).find_each do |snapshot|
        establishment = snapshot.establishment
        next unless establishment.ec.start_with?("3")

        paired_ec = "9#{establishment.ec[1..]}"
        next unless Establishment.exists?(ec: paired_ec, company_id: establishment.company_id)

        Anomalies.record!(
          batch: @batch, type: "ec_duplicate_candidate", severity: "atencao",
          company: establishment.company, establishment:,
          details: { paired_ec: }
        )
      end
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
      snapshots.includes(:establishment, :sub_channel).find_each do |snapshot|
        previous = MapSnapshot.where(establishment: snapshot.establishment)
          .where.not(import_batch: @batch).order(id: :desc).first
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
