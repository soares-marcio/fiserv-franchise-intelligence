module Platform
  # Suporte da plataforma às contas de organização. Quem perde o celular é o administrador
  # da organização, e ninguém dentro dela pode reiniciar o segundo fator dele.
  class UsersController < ApplicationController
    before_action :load_user

    def reset_mfa
      authorize @user, :support?
      @user.reset_mfa!
      Audit.record("user.mfa_reset", record: @user, request:, metadata: { alvo: @user.email_address })
      redirect_to platform_organization_path(@user.organization),
        notice: "Segundo fator reiniciado. A pessoa cadastra de novo ao entrar."
    end

    def deactivate
      authorize @user, :support?
      @user.deactivate!
      Audit.record("user.deactivated", record: @user, request:, metadata: { alvo: @user.email_address })
      redirect_to platform_organization_path(@user.organization), notice: "Acesso desativado."
    end

    def reactivate
      authorize @user, :support?
      @user.reactivate!
      Audit.record("user.reactivated", record: @user, request:, metadata: { alvo: @user.email_address })
      redirect_to platform_organization_path(@user.organization), notice: "Acesso reativado."
    end

    private

    # Sem policy_scope: a plataforma não lista usuários por aqui, só age sobre um. A regra de
    # quem ela alcança é support?, e conta da plataforma não passa por ela.
    def load_user
      @user = User.find_param!(params[:id])
    end
  end
end
