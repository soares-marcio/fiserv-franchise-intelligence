module BinImport
  class ChannelResolver
    # Nome de um canal criado sem CANAL na planilha. A carteira entra e fica visível, em vez
    # de o arquivo inteiro ser recusado por uma coluna vazia; o analista vê pelo nome que
    # falta definir o canal, e as linhas sem CANAL viram anomalia no mesmo import.
    FALLBACK_NAME = "SEM CANAL".freeze

    # O REPORT_ID é a identidade do canal. Sem CANAL na planilha, um REPORT_ID já conhecido
    # mantém o nome que tem — uma planilha incompleta não pode renomear a carteira.
    #
    # Quem decide se o ator pode tocar o Master é este método, antes de qualquer gravação:
    # Master de outra organização é recusado sem revelar nome nenhum (a mensagem vai para a
    # tela de lotes); Master existente exige tê-lo inteiro; Master novo só o administrador
    # da organização cria — a planilha é a carteira inteira, e um colaborador não a inaugura.
    # Sem ator (console, cadastro manual, teste) a checagem de escopo não se aplica.
    def self.call(report_id:, name:, organization:, actor: nil)
      # Só entre os ativos: o REPORT_ID de um Master apagado nasce como Master novo.
      channel = Channel.active.find_by(external_id: report_id)
      if channel && channel.organization_id != organization.id
        raise ArgumentError, "O REPORT_ID deste arquivo não pertence à sua organização. Confira se a " \
          "planilha enviada é a da sua carteira."
      end
      authorize!(channel, actor)
      return channel if channel && name.blank?

      resolved = name.presence || FALLBACK_NAME
      if channel && channel.name != resolved
        raise ArgumentError, "O REPORT_ID #{report_id} já pertence ao canal \"#{channel.name}\", " \
          "e este arquivo traz \"#{resolved}\". Um REPORT_ID identifica uma carteira só: " \
          "confira se o CANAL da planilha está correto."
      end

      # Master novo volta sem salvar: quem o grava é a mesma transação que grava os dados do
      # arquivo. Planilha que falha na validação não deixa um Master vazio para trás
      # (homologação de 01/10/2026: um EC duplicado criou "MASTER RAMOS E SILVA" sem dado).
      channel || Channel.new(external_id: report_id, name: resolved, organization:)
    end

    def self.authorize!(channel, actor)
      return if actor.nil?

      scope = AccessScope.for(actor)
      if channel
        return if scope.whole?(channel.id)

        raise ArgumentError, "Esta planilha é do Master \"#{channel.name}\" inteiro, que está fora " \
          "do seu acesso — um MIC dele não basta. Confira o arquivo ou peça a liberação desse Master."
      end
      return if scope.organization_wide?

      raise ArgumentError, "Este arquivo é de um Master que ainda não existe na sua organização. O " \
        "primeiro arquivo de um Master novo é enviado pelo administrador da organização."
    end
    private_class_method :authorize!
  end
end
