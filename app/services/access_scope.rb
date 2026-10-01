# O escopo de dados de um ator: quais Masters inteiros e quais MICs avulsos ele enxerga,
# dentro de qual organização.
#
# É construído uma vez por requisição, com uma consulta só, e atravessa os query objects no
# lugar do antigo `channel_id:`. A troca de assinatura é proposital: quem esquecer de migrar
# um ponto quebra no boot, e não em produção servindo dado de outro Master.
#
# Não existe escopo "tudo": o administrador da organização recebe a lista real dos Masters
# dela, e a conta da plataforma recebe escopo vazio. Um "tudo" simbólico exigiria um ramo
# especial em cada predicado — e é num ramo desses que o dado de uma organização vazaria
# para outra.
class AccessScope
  # Nunca instanciado a partir de params: o escopo vem das concessões do usuário, e o filtro
  # da tela só estreita o que já é permitido.
  def self.for(user)
    return empty if user.nil? || user.platform_admin?
    return organization_wide(user.organization) if user.organization_admin?

    grants = user.access_grants.pluck(:channel_id, :sub_channel_id)
    full = grants.filter_map { |channel_id, sub_channel_id| channel_id if sub_channel_id.nil? }.uniq
    # MIC de um Master que o ator já tem inteiro é redundante: some daqui para o predicado
    # não carregar CTE à toa.
    subs = grants.filter_map { |channel_id, sub| sub if sub && full.exclude?(channel_id) }.uniq
    new(organization_id: user.organization_id, full_channel_ids: full, sub_channel_ids: subs)
  end

  def self.empty = new

  # O administrador da organização enxerga a organização inteira — materializada como a
  # lista real dos Masters dela: assim todo predicado que já recorta por canal recorta
  # também a organização, sem ramo especial.
  def self.organization_wide(organization)
    new(organization_id: organization.id, organization_wide: true,
      full_channel_ids: Channel.where(organization_id: organization.id).pluck(:id), sub_channel_ids: [])
  end

  attr_reader :organization_id, :full_channel_ids, :sub_channel_ids

  def initialize(organization_id: nil, full_channel_ids: [], sub_channel_ids: [], organization_wide: false)
    @organization_id = organization_id
    @full_channel_ids = full_channel_ids
    @sub_channel_ids = sub_channel_ids
    @organization_wide = organization_wide
  end

  # Só importa onde a lista de canais não responde: um Master que ainda não existe.
  def organization_wide? = @organization_wide

  def empty? = full_channel_ids.empty? && sub_channel_ids.empty?

  # Recorte por MIC obriga a passar pelo vínculo EC→MIC, que é temporal; sem ele, o
  # predicado é uma comparação de canal e usa os índices que já existem.
  def partial? = sub_channel_ids.any?

  # O Master inteiro, e não um MIC dele. É a pergunta certa para tudo que não tem recorte
  # por MIC — a planilha importada é a carteira inteira num arquivo, e a revisão de um lote
  # mostra o diff do Master todo.
  def whole?(channel_id)
    full_channel_ids.include?(channel_id)
  end

  # Todos os canais alcançáveis, por qualquer via. Serve ao seletor de canal da tela e aos
  # filtros que só precisam do Master.
  def channel_ids
    @channel_ids ||= (full_channel_ids + SubChannel.where(id: sub_channel_ids).pluck(:channel_id)).uniq
  end

  # O filtro da tela estreita o que já é permitido; jamais amplia. Um canal fora do escopo
  # devolve um recorte vazio em vez de silenciosamente virar "todos".
  def narrow(channel: nil, sub_channel: nil)
    return narrow_to_sub_channel(sub_channel) if sub_channel
    return self if channel.nil?

    if full_channel_ids.include?(channel.id)
      derived(full_channel_ids: [ channel.id ])
    else
      allowed_ids = SubChannel.where(id: sub_channel_ids, channel_id: channel.id).pluck(:id)
      derived(sub_channel_ids: allowed_ids)
    end
  end

  # Duas pessoas com o mesmo recorte compartilham cache — é o desejado, e evita uma entrada
  # por usuário. O id do ator nunca entra: o que separa é o escopo, não quem o tem. A
  # organização entra porque duas organizações nunca podem dividir uma entrada.
  def cache_key
    "org:#{organization_id || '-'}|c:#{full_channel_ids.sort.join(',')}|s:#{sub_channel_ids.sort.join(',')}"
  end

  # O SQL cru recorta pelos mesmos ECs que o Active Record recortaria: a regra vive em
  # Establishment.in_scope e este método só a empacota como CTE.
  def establishments_cte
    "scoped_establishments AS (#{Establishment.in_scope(self).select(:id).to_sql})"
  end

  private

  # Escopo estreitado pela tela: herda a organização e perde o "inteiro".
  def derived(full_channel_ids: [], sub_channel_ids: [])
    AccessScope.new(organization_id:, full_channel_ids:, sub_channel_ids:)
  end

  def narrow_to_sub_channel(sub_channel)
    allowed = full_channel_ids.include?(sub_channel.channel_id) || sub_channel_ids.include?(sub_channel.id)
    return derived unless allowed

    derived(sub_channel_ids: [ sub_channel.id ])
  end
end
