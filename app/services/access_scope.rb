# O escopo de dados de um ator: quais Masters inteiros e quais MICs avulsos ele enxerga.
#
# É construído uma vez por requisição, com uma consulta só, e atravessa os query objects no
# lugar do antigo `channel_id:`. A troca de assinatura é proposital: quem esquecer de migrar
# um ponto quebra no boot, e não em produção servindo dado de outro Master.
class AccessScope
  # Nunca instanciado a partir de params: o escopo vem das concessões do usuário, e o filtro
  # da tela só estreita o que já é permitido.
  def self.for(user)
    return everything if user&.super_admin?
    return new(full_channel_ids: [], sub_channel_ids: []) if user.nil?

    grants = user.access_grants.pluck(:channel_id, :sub_channel_id)
    full = grants.filter_map { |channel_id, sub_channel_id| channel_id if sub_channel_id.nil? }.uniq
    # MIC de um Master que o ator já tem inteiro é redundante: some daqui para o predicado
    # não carregar CTE à toa.
    subs = grants.filter_map { |channel_id, sub| sub if sub && full.exclude?(channel_id) }.uniq
    new(full_channel_ids: full, sub_channel_ids: subs)
  end

  def self.everything = new(everything: true)

  attr_reader :full_channel_ids, :sub_channel_ids

  def initialize(full_channel_ids: [], sub_channel_ids: [], everything: false)
    @full_channel_ids = full_channel_ids
    @sub_channel_ids = sub_channel_ids
    @everything = everything
  end

  def everything? = @everything

  def empty? = !everything? && full_channel_ids.empty? && sub_channel_ids.empty?

  # Recorte por MIC obriga a passar pelo vínculo EC→MIC, que é temporal; sem ele, o
  # predicado é uma comparação de canal e usa os índices que já existem.
  def partial? = !everything? && sub_channel_ids.any?

  # Todos os canais alcançáveis, por qualquer via. Serve ao seletor de canal da tela e aos
  # filtros que só precisam do Master.
  def channel_ids
    return @channel_ids if defined?(@channel_ids)

    @channel_ids = if everything?
      Channel.pluck(:id)
    else
      (full_channel_ids + SubChannel.where(id: sub_channel_ids).pluck(:channel_id)).uniq
    end
  end

  # O filtro da tela estreita o que já é permitido; jamais amplia. Um canal fora do escopo
  # devolve um recorte vazio em vez de silenciosamente virar "todos".
  def narrow(channel: nil, sub_channel: nil)
    return narrow_to_sub_channel(sub_channel) if sub_channel
    return self if channel.nil?
    return AccessScope.new(full_channel_ids: [ channel.id ], sub_channel_ids: []) if everything?

    if full_channel_ids.include?(channel.id)
      AccessScope.new(full_channel_ids: [ channel.id ], sub_channel_ids: [])
    else
      permitidos = SubChannel.where(id: sub_channel_ids, channel_id: channel.id).pluck(:id)
      AccessScope.new(full_channel_ids: [], sub_channel_ids: permitidos)
    end
  end

  # Duas pessoas com o mesmo recorte compartilham cache — é o desejado, e evita uma entrada
  # por usuário. O id do ator nunca entra: o que separa é o escopo, não quem o tem.
  def cache_key
    return "all" if everything?

    "c:#{full_channel_ids.sort.join(',')}|s:#{sub_channel_ids.sort.join(',')}"
  end

  # O SQL cru recorta pelos mesmos ECs que o Active Record recortaria: a regra vive em
  # Establishment.in_scope e este método só a empacota como CTE.
  def establishments_cte
    "scoped_establishments AS (#{Establishment.in_scope(self).select(:id).to_sql})"
  end

  private

  def narrow_to_sub_channel(sub_channel)
    permitido = everything? || full_channel_ids.include?(sub_channel.channel_id) ||
      sub_channel_ids.include?(sub_channel.id)
    return AccessScope.new(full_channel_ids: [], sub_channel_ids: []) unless permitido

    AccessScope.new(full_channel_ids: [], sub_channel_ids: [ sub_channel.id ])
  end
end
