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
      company_ids = snapshots.joins(establishment: :company).group("companies.id")
        .having("COUNT(DISTINCT sub_channel_id) > 1").pluck("companies.id")
      return if company_ids.empty?

      # Duas consultas para todas as empresas divergentes: era um Company.find e uma lista de
      # subcanais por empresa, dentro da transação do import.
      names_by_company = sub_channel_names_by_company(company_ids)

      Company.where(id: company_ids).find_each do |company|
        Anomalies.record!(
          batch: @batch, type: "company_in_multiple_sub_channels", severity: "atencao",
          company:, details: { sub_channels: names_by_company.fetch(company.id, []) }
        )
      end
    end

    def sub_channel_names_by_company(company_ids)
      snapshots.joins(:establishment, :sub_channel)
        .where(establishments: { company_id: company_ids })
        .distinct.order("sub_channels.name")
        .pluck("establishments.company_id", "sub_channels.name")
        .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
    end

    def detect_changed_sub_channels!
      current = snapshots.includes(:establishment, :sub_channel).to_a
      previous_by_establishment = previous_sub_channels

      current.each do |snapshot|
        previous_id, previous_name = previous_by_establishment[snapshot.establishment_id]
        next unless previous_id && previous_id != snapshot.sub_channel_id

        Anomalies.record!(
          batch: @batch, type: "ec_changed_sub_channel", severity: "info",
          company: snapshot.establishment.company, establishment: snapshot.establishment,
          details: { previous: previous_name, current: snapshot.sub_channel.name }
        )
      end
    end

    # Só o snapshot imediatamente anterior de cada EC do lote: a história inteira do Mapa,
    # que cresce a cada planilha semanal, fica no banco.
    def previous_sub_channels
      MapSnapshot.where(establishment_id: snapshots.select(:establishment_id))
        .where.not(import_batch: @batch).joins(:sub_channel)
        .select("DISTINCT ON (map_snapshots.establishment_id) map_snapshots.establishment_id, " \
          "map_snapshots.sub_channel_id, sub_channels.name")
        .order("map_snapshots.establishment_id, map_snapshots.id DESC")
        .map { |row| [ row.establishment_id, [ row.sub_channel_id, row.name ] ] }.to_h
    end

    def snapshots
      @snapshots ||= MapSnapshot.where(import_batch: @batch)
    end
  end
end
