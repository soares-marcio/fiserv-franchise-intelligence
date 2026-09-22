# Os predicados de recorte, em um lugar só. Seis consultas precisam deles, e a regra
# repetida seis vezes divergiria na primeira correção feita em cinco delas.
#
# Quem inclui precisa ter @scope (um AccessScope).
module ScopedQuery
  # Binds do recorte. Toda consulta recebe os três, mesmo usando um só: assim acrescentar um
  # predicado não obriga a lembrar de acrescentar bind.
  def scope_binds
    {
      channel_ids: bind_list(@scope.everything? ? nil : @scope.channel_ids),
      full_channel_ids: bind_list(@scope.full_channel_ids),
      sub_channel_ids: bind_list(@scope.sub_channel_ids)
    }
  end

  # Tabelas que só têm channel_id. O recorte por MIC herda o canal: cobertura do mês e dia
  # de corte são do arquivo, que é do Master inteiro.
  def channel_predicate(prefix = nil)
    return "TRUE" if @scope.everything?

    "#{qualify(prefix)}channel_id IN (:channel_ids)"
  end

  # Tabelas com sub_channel_id: Master inteiro pelo canal, MIC avulso pela coluna.
  def sub_channel_predicate(prefix = nil)
    return "TRUE" if @scope.everything?

    "(#{qualify(prefix)}channel_id IN (:full_channel_ids) OR " \
      "#{qualify(prefix)}sub_channel_id IN (:sub_channel_ids))"
  end

  # Tabelas ligadas ao EC e sem sub_channel_id — o faturamento diário consolidado é a
  # principal: o recorte fino passa pelo vínculo EC→MIC, que é temporal.
  def establishment_predicate(prefix)
    return "TRUE" if @scope.everything?
    return "#{qualify(prefix)}channel_id IN (:channel_ids)" unless @scope.partial?

    "(#{qualify(prefix)}channel_id IN (:full_channel_ids) OR " \
      "#{qualify(prefix)}establishment_id IN (SELECT id FROM scoped_establishments))"
  end

  # Prefixo do CTE, vazio quando não há recorte por MIC: sem MIC, nenhuma consulta precisa
  # dele, e um CTE inútil é trabalho a mais no plano de execução.
  def establishments_cte
    @scope.partial? ? "WITH #{@scope.establishments_cte} " : ""
  end

  # Predicado com os ids já embutidos, para as consultas que usam binds posicionais ($1,
  # $2) e não aceitam lista nomeada. Os ids vêm das concessões, nunca de params, e ainda
  # assim passam pelo sanitize.
  def literal_predicate(predicate)
    ApplicationRecord.sanitize_sql_array([ predicate, scope_binds ])
  end

  private

  # Lista vazia não existe em SQL: `IN ()` é erro de sintaxe. Zero não é id de nada, então a
  # comparação fica falsa — que é o que escopo vazio deve enxergar.
  def bind_list(ids)
    return [ 0 ] if ids.nil? || ids.empty?

    ids
  end

  def qualify(prefix)
    prefix.present? ? "#{prefix}." : ""
  end
end
