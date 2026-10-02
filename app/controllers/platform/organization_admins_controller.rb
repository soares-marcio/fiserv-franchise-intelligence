module Platform
  # Mais um administrador para uma organização que já existe — inclusive a organização
  # inicial, criada pela migration com os dados que já estavam no portal.
  class OrganizationAdminsController < ApplicationController
    before_action :load_organization

    def new
      authorize @organization, :create_admin?
      @admin = User.new
    end

    def create
      authorize @organization, :create_admin?
      admin = Operations::CreateOrganizationAdmin.call(**admin_params, organization: @organization, actor: Current.user)
      Audit.record("organization_admin.created", record: admin, request:, metadata: { alvo: admin.email_address })
      redirect_to platform_organization_path(@organization),
        notice: "Administrador criado. A senha provisória de #{admin.name} fica nesta tela até a troca."
    rescue ActiveRecord::RecordInvalid => error
      @admin = error.record
      render :new, status: :unprocessable_entity
    end

    private

    def load_organization
      @organization = policy_scope(Organization).find_param!(params[:organization_id])
    end

    def admin_params
      params.require(:user).permit(:name, :email_address).to_h.symbolize_keys
    end
  end
end
