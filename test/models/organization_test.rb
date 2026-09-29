require "test_helper"

# A organização é a unidade de isolamento. Os testes aqui são sobre as invariantes que o
# banco e o modelo garantem juntos — o resto (quem vê o quê) fica nos testes de tela.
class OrganizationTest < ActiveSupport::TestCase
  test "nasce sem nome, e nome em branco não é nome" do
    org = Organization.create!
    assert_not org.named?

    org.name = "   "
    assert_not org.valid?

    org.name = "Franquia Norte"
    assert org.save
    assert org.named?
  end

  test "conta da plataforma não tem organização; conta comum precisa de uma" do
    plataforma = User.new(email_address: "p@exemplo.com", name: "P", password: "senha-bem-longa-1",
      platform_admin: true, organization: default_organization)
    assert_not plataforma.valid?
    assert_includes plataforma.errors[:organization].join, "plataforma"

    comum = User.new(email_address: "c@exemplo.com", name: "C", password: "senha-bem-longa-1")
    assert_not comum.valid?
    assert_includes comum.errors[:organization].join, "obrigatória"

    admin = User.new(email_address: "a@exemplo.com", name: "A", password: "senha-bem-longa-1",
      platform_admin: true, organization_admin: true)
    assert_not admin.valid?, "a plataforma não administra organização"
  end

  # As FKs compostas: usuário e Master de organizações diferentes não se ligam nem por
  # console — a validação do modelo dá a mensagem, o banco dá a garantia.
  test "concessão a Master de outra organização é recusada pelo modelo e pelo banco" do
    outra = Organization.create!(name: "Outra")
    canal_alheio = Channel.create!(organization: outra, external_id: "9001", name: "MASTER ALHEIO")
    pessoa = create_user(email: "pessoa@exemplo.com")

    grant = AccessGrant.new(user: pessoa, channel: canal_alheio)
    assert_not grant.valid?
    assert_includes grant.errors[:channel].join, "outra organização"

    assert_raises(ActiveRecord::InvalidForeignKey) do
      AccessGrant.insert!({ user_id: pessoa.id, channel_id: canal_alheio.id, organization_id: outra.id,
        created_at: Time.current, updated_at: Time.current })
    end
  end

  test "lote e Master de organizações diferentes não se ligam" do
    outra = Organization.create!(name: "Outra")
    canal_alheio = Channel.create!(organization: outra, external_id: "9001", name: "MASTER ALHEIO")

    assert_raises(ActiveRecord::InvalidForeignKey) do
      ImportBatch.insert!({ organization_id: default_organization.id, channel_id: canal_alheio.id,
        source_filename: "x.xlsx", file_checksum: "x-1", status: "failed",
        created_at: Time.current, updated_at: Time.current })
    end
  end
end
