module Platform
  # Suporte da plataforma às contas de organização. Quem perde o celular é o administrador
  # da organização, e ninguém dentro dela pode reiniciar o segundo fator dele.
  class UsersController < ApplicationController
    before_action :load_user

    # A linha do tempo de uma conta de organização: o ciclo de vida dela, não o que ela fez
    # na carteira. A regra de quem a plataforma alcança é a mesma do suporte.
    def show
      authorize @user, :support?
      @timeline = AccountTimeline.new(@user)
    end

    def reset_mfa
      authorize @user, :support?
      @user.reset_mfa!
      Audit.record("user.mfa_reset", record: @user, request:, metadata: { alvo: @user.email_address })
      redirect_to platform_organization_path(@user.organization),
        notice: "Segundo fator reiniciado. A pessoa cadastra de novo ao entrar."
    end

    # Desativar o último administrador ativo suspende a organização junto: o motivo de
    # desativá-lo (desinteresse, inadimplência) vale para todos abaixo dele, e sem isso os
    # convidados continuariam entrando numa organização que ninguém mais administra.
    def deactivate
      authorize @user, :support?
      @user.deactivate!
      Audit.record("user.deactivated", record: @user, request:, metadata: { alvo: @user.email_address })
      organization = @user.organization
      if @user.organization_admin? && !organization.users.active.where(organization_admin: true).exists?
        organization.suspend!
        Audit.record("organization.suspended", record: organization, request:,
          metadata: { motivo: "último administrador desativado" })
        return redirect_to platform_organization_path(organization),
          notice: "Acesso desativado. Era o último administrador: a organização foi suspensa junto, " \
            "e ninguém dela entra até a reativação."
      end
      redirect_to platform_organization_path(organization), notice: "Acesso desativado."
    end

    # O caminho de volta é simétrico: reativar um administrador reabre a organização que
    # estava suspensa, senão ele continuaria do lado de fora.
    def reactivate
      authorize @user, :support?
      @user.reactivate!
      Audit.record("user.reactivated", record: @user, request:, metadata: { alvo: @user.email_address })
      organization = @user.organization
      if @user.organization_admin? && organization.suspended?
        organization.reactivate!
        Audit.record("organization.reactivated", record: organization, request:,
          metadata: { motivo: "administrador reativado" })
        return redirect_to platform_organization_path(organization),
          notice: "Acesso reativado, e a organização reaberta junto."
      end
      redirect_to platform_organization_path(organization), notice: "Acesso reativado."
    end

    private

    # Sem policy_scope: a plataforma não lista usuários por aqui, só age sobre um. A regra de
    # quem ela alcança é support?, e conta da plataforma não passa por ela.
    def load_user
      @user = User.find_param!(params[:id])
    end
  end
end
