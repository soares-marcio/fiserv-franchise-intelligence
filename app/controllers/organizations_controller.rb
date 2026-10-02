# O nome da organização. Ela nasce sem nome, criada pela plataforma; quem a nomeia é o seu
# administrador, no primeiro acesso, depois da senha e do segundo fator — é a última tela
# antes do portal. Mudar o nome depois é por console, de propósito.
class OrganizationsController < ApplicationController
  layout "auth"

  before_action :load_organization

  def edit
    authorize @organization, :update?
  end

  def update
    authorize @organization, :update?
    # Sem `presence`: nome em branco precisa chegar ao modelo como string vazia, que ele
    # recusa — nulo seria "ainda sem nome", e passaria.
    if @organization.update(name: params[:name].to_s.strip)
      Audit.record("organization.named", record: @organization, request:, metadata: { nome: @organization.name })
      redirect_to root_path, notice: "Organização nomeada. Bem-vindo."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  # A conta da plataforma não tem organização: sem registro para autorizar, a resposta é a
  # mesma de qualquer tela que não é dela.
  def load_organization
    @organization = Current.organization
    raise Pundit::NotAuthorizedError if @organization.nil?
  end
end
