class Current < ActiveSupport::CurrentAttributes
  attribute :session
  delegate :user, to: :session, allow_nil: true

  # Uma consulta por requisição, e não uma por tela: o escopo é lido das concessões na
  # primeira vez que alguém pergunta e vale até o fim da requisição. O CurrentAttributes
  # é reiniciado a cada requisição, então não há risco de um escopo sobreviver ao ator.
  def access_scope
    @access_scope ||= AccessScope.for(user)
  end
end
