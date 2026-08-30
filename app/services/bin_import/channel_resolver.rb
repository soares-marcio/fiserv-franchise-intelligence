module BinImport
  class ChannelResolver
    def self.call(report_id:, canal:)
      channel = Channel.find_by(external_id: report_id)
      if channel && channel.canal != canal
        raise ArgumentError, "REPORT_ID #{report_id} associado a outro CANAL"
      end

      channel || Channel.create!(external_id: report_id, canal:)
    end
  end
end
