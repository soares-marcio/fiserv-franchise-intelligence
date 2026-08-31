module BinImport
  class Consolidator
    def initialize(batch)
      @batch = batch
      @now = Time.current
    end

    def call
      consolidate_daily!
      consolidate_monthly!
      update_coverages!
    end

    private

    def consolidate_daily!
      revenues = DailyRevenue.where(import_batch: @batch).to_a
      establishment_ids = revenues.map(&:establishment_id).uniq
      existing = existing_daily(establishment_ids).index_by { |row| daily_key(row) }
      incoming = revenues.index_by { |row| daily_key(row) }
      previous_coverages = coverages_by_period
      revisions = daily_revisions(existing, incoming, previous_coverages, establishment_ids)
      DailyRevenueRevision.insert_all!(revisions) if revisions.any?
      replace_daily_rows!(incoming, existing, establishment_ids)
    end

    def existing_daily(establishment_ids)
      DailyRevenueConsolidated.where(
        channel_id: @batch.channel_id,
        establishment_id: establishment_ids,
        period: [ @batch.previous_period, @batch.current_period ]
      ).to_a
    end

    def daily_revisions(existing, incoming, coverages, establishment_ids)
      covered_keys(existing, incoming, establishment_ids).filter_map do |key|
        old_row = existing[key]
        new_row = incoming[key]
        next if old_row&.provisional == false && new_row&.provisional

        old_known = old_row.present? || coverages.fetch(key[1], 0) >= key[2]
        old_amount = old_row&.amount || 0
        new_amount = new_row&.amount || 0
        next unless old_known && old_amount != new_amount

        { establishment_id: key[0], period: key[1], day: key[2], previous_amount: old_amount,
          new_amount: new_amount, import_batch_id: @batch.id, detected_at: @now }
      end
    end

    def covered_keys(existing, incoming, establishment_ids)
      keys = incoming.keys
      existing.each_key do |key|
        cutoff = key[1] == @batch.current_period ? @batch.current_month_cutoff_day : 31
        keys << key if establishment_ids.include?(key[0]) && key[2] <= cutoff
      end
      keys.uniq
    end

    def replace_daily_rows!(incoming, existing, establishment_ids)
      delete_daily_scope(@batch.previous_period, 31, establishment_ids)
      delete_daily_scope(@batch.current_period, @batch.current_month_cutoff_day, establishment_ids, provisional: true)
      rows = incoming.filter_map do |key, row|
        next if existing[key]&.provisional == false && row.provisional

        { establishment_id: row.establishment_id, channel_id: row.channel_id,
          period: row.period, day: row.day, amount: row.amount, provisional: row.provisional,
          source_import_batch_id: @batch.id, revised_count: revision_count(existing[key], row),
          created_at: @now, updated_at: @now }
      end
      DailyRevenueConsolidated.upsert_all(rows, unique_by: "index_daily_revenues_consolidated_primary") if rows.any?
    end

    def delete_daily_scope(period, cutoff, establishment_ids, provisional: nil)
      scope = DailyRevenueConsolidated.where(
        channel_id: @batch.channel_id, period:, establishment_id: establishment_ids, day: 1..cutoff
      )
      scope = scope.where(provisional:) unless provisional.nil?
      scope.delete_all
    end

    def revision_count(old_row, new_row)
      changed = old_row && old_row.amount != new_row.amount
      old_row&.revised_count.to_i + (changed ? 1 : 0)
    end

    def consolidate_monthly!
      rows = MonthlyVolume.where(import_batch: @batch).to_a
      existing = MonthlyVolumeConsolidated.where(
        channel_id: @batch.channel_id, establishment_id: rows.map(&:establishment_id).uniq,
        period: rows.map(&:period).uniq
      ).index_by { |row| monthly_key(row) }
      record_closed_month_revisions(rows, existing)
      upserts = monthly_upserts(rows)
      MonthlyVolumeConsolidated.upsert_all(upserts,
        unique_by: "index_monthly_volumes_consolidated_primary") if upserts.any?
    end

    def record_closed_month_revisions(rows, existing)
      rows.each do |row|
        old = existing[monthly_key(row)]
        next unless old && old.amount != row.amount && row.period < @batch.current_period

        Anomalies.record!(batch: @batch, type: "closed_period_revised", severity: "atencao",
          establishment: row.establishment,
          details: { period: row.period, metric: row.metric, previous_amount: old.amount, new_amount: row.amount })
      end
    end

    def monthly_upserts(rows)
      rows.map do |row|
        { channel_id: row.channel_id, establishment_id: row.establishment_id,
          period: row.period, metric: row.metric, amount: row.amount,
          source_import_batch_id: @batch.id, created_at: @now, updated_at: @now }
      end
    end

    def update_coverages!
      [ [ @batch.previous_period, 31, true ],
        [ @batch.current_period, @batch.current_month_cutoff_day, false ] ].each do |period, cutoff, closed|
        current = PeriodCoverage.find_by(channel_id: @batch.channel_id, period:)
        record_shorter_batch!(current, cutoff) if current && cutoff < current.max_known_day
        PeriodCoverage.upsert(
          { channel_id: @batch.channel_id, period:,
            max_known_day: [ current&.max_known_day.to_i, cutoff ].max,
            closed: current&.closed || closed,
            last_import_batch_id: coverage_batch_id(current, cutoff, closed),
            created_at: current&.created_at || @now, updated_at: @now },
          unique_by: "index_period_coverages_on_channel_id_and_period"
        )
      end
    end

    def record_shorter_batch!(coverage, cutoff)
      Anomalies.record!(batch: @batch, type: "batch_covers_fewer_days", severity: "info",
        details: { period: coverage.period, previous: coverage.max_known_day, current: cutoff })
    end

    def coverage_batch_id(current, cutoff, closed)
      return @batch.id if current.nil? || cutoff > current.max_known_day || (closed && !current.closed)

      current.last_import_batch_id
    end

    def coverages_by_period
      PeriodCoverage.where(channel_id: @batch.channel_id,
        period: [ @batch.previous_period, @batch.current_period ]).pluck(:period, :max_known_day).to_h
    end

    def daily_key(row)
      [ row.establishment_id, row.period, row.day ]
    end

    def monthly_key(row)
      [ row.establishment_id, row.period, row.metric ]
    end
  end
end
