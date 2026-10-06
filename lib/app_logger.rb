# Logger de produção: saída padrão sempre e, quando há arquivo, também ele, girado por dia.
#
# A marcação (`[request_id]`) envolve o broadcast, e não cada destino: com um TaggedLogging
# por destino, o BroadcastLogger repassa o bloco de `tagged` a cada um deles, e o Rails
# executaria a requisição inteira uma vez por destino.
module AppLogger
  def self.build(io, file:)
    destinations = [ ActiveSupport::Logger.new(io) ]
    destinations << ActiveSupport::Logger.new(file, "daily") if file
    ActiveSupport::TaggedLogging.new(ActiveSupport::BroadcastLogger.new(*destinations))
  end
end
