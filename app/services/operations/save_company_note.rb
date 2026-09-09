module Operations
  # Anotação do analista sobre o cliente: uma por CNPJ, editável por cima — gravar substitui,
  # não acumula (decisão do usuário). Sem autor, porque o portal não tem autenticação: fica só
  # a hora da última edição, como establishments.duplicate_confirmed_at.
  class SaveCompanyNote
    NAME = "salvar_anotacao_do_cliente".freeze
    # O corpo é HTML do editor, então o limite conta marcação junto. 20 mil caracteres são
    # umas quatro páginas de texto — folgado para uma anotação e curto o bastante para a
    # coluna não virar depósito de documento.
    MAX_LENGTH = 20_000

    def self.call(cnpj:, body:)
      cnpj = cnpj.to_s
      raise ArgumentError, "CNPJ inválido para anotação." unless cnpj.match?(/\A\d{14}\z/)

      if body.to_s.length > MAX_LENGTH
        raise ArgumentError,
          "A anotação tem #{body.to_s.length} caracteres e o limite é #{MAX_LENGTH}."
      end

      note = CompanyNote.find_or_initialize_by(cnpj:)
      # Editor esvaziado é o gesto de apagar: some a anotação e, com ela, os anexos. Não há
      # botão de excluir na tela porque o formulário já dá esse caminho.
      return note.destroy && nil if blank_body?(body)

      note.body = body
      note.save!
      note
    end

    # O Trix nunca manda string vazia: um editor limpo chega como "<div><br></div>". Quem
    # decide se há conteúdo é o texto puro, já sem marcação nem anexo.
    def self.blank_body?(body)
      rich = ActionText::Content.new(body.to_s)
      rich.to_plain_text.strip.empty? && rich.attachments.empty?
    end
    private_class_method :blank_body?
  end
end
