module Operations
  # A única via para alguém virar administrador de organização: a plataforma cria a conta —
  # numa organização nova, ainda sem nome, ou numa que já existe. O convite comum nunca
  # concede esse papel.
  #
  # A senha provisória é gerada aqui e fica na conta até a pessoa trocá-la no primeiro
  # acesso, como no convite; a plataforma a vê na tela da organização para entregar.
  class CreateOrganizationAdmin
    def self.call(name:, email_address:, actor:, organization: nil)
      senha = SecureRandom.alphanumeric(14)
      ApplicationRecord.transaction do
        organization ||= Organization.create!
        User.create!(
          name:, email_address:, password: senha, provisional_password: senha,
          must_change_password: true, organization:, organization_admin: true, created_by: actor
        )
      end
    end
  end
end
