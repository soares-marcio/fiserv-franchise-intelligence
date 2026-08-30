module BinImport
  class Cutoff
    def self.day(revenue_rows)
      (1..31).select do |day|
        revenue_rows.any? do |row|
          (Normalizer.decimal(row[format("DIA %02d", day)]) || 0).nonzero?
        end
      end.max || 1
    end
  end
end
