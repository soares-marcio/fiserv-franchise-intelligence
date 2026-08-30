module BinImport
  class ChannelResolver
    def self.call(report_id:, name:)
      channel = Channel.find_by(external_id: report_id)
      if channel && channel.name != name
        raise ArgumentError, "REPORT_ID #{report_id} associado a outro CANAL"
      end

      channel || Channel.create!(external_id: report_id, name:)
    end
  end
end
