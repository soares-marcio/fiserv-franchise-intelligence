module BinImport
  class Normalizer
    class << self
      # Célula numérica do Excel chega sem os zeros à esquerda; identificadores de
      # largura fixa precisam ser repostos ao tamanho original.
      WIDTHS = { ec: 8, cnpj: 14, cep: 8 }.freeze

      def digits(value, width: nil)
        case value
        when Integer then pad(value.to_s, width)
        when Float then pad(value.to_i.to_s, width)
        else value.to_s.gsub(/\D/, "")
        end
      end

      # Só o valor numérico perdeu zeros; texto já veio com o que a origem tinha.
      def pad(digits, width)
        return digits if width.nil? || digits.empty? || digits.length >= width

        digits.rjust(width, "0")
      end

      def ec(value)
        digits(value, width: WIDTHS[:ec])
      end

      def cnpj(value)
        digits(value, width: WIDTHS[:cnpj])
      end

      def cep(value)
        digits(value, width: WIDTHS[:cep])
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
