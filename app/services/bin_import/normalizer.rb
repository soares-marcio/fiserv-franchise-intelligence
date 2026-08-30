module BinImport
  class Normalizer
    class << self
      def digits(value)
        case value
        when Integer then value.to_s
        when Float then value.to_i.to_s
        else value.to_s.gsub(/\D/, "")
        end
      end

      def decimal(value)
        return nil if value.blank?
        return BigDecimal(value.to_s) if value.is_a?(Numeric)

        normalized = value.to_s.include?(",") ? value.to_s.delete(".").tr(",", ".") : value.to_s
        BigDecimal(normalized)
      rescue ArgumentError
        nil
      end

      def date(value)
        return value.to_date if value.respond_to?(:to_date)
        return nil if value.blank?

        Date.parse(value.to_s)
      rescue Date::Error
        nil
      end

      def datetime(value)
        return value.to_time if value.respond_to?(:to_time)
        return nil if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def integer(value)
        decimal(value)&.to_i
      end

      def boolean(value)
        value.to_s.strip.upcase.in?([ "SIM", "ATIVO", "TRUE" ])
      end
    end
  end
end
