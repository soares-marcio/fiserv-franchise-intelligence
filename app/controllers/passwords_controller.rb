# Troca da própria senha. É obrigatória no primeiro acesso, porque a senha inicial passou
# pelas mãos de quem convidou — e continua disponível depois, para quem quiser trocar.
class PasswordsController < ApplicationController
  layout "auth"

  # Entrar não é uma ação autorizável: quem chega aqui ainda não tem permissões.
  skip_after_action :verify_authorized

  def edit
  end

  def update
    unless Current.user.authenticate(params[:current_password].to_s)
      redirect_to edit_password_path, alert: "A senha atual não confere."
      return
    end

    if Current.user.update(password: params[:password], password_confirmation: params[:password_confirmation],
        must_change_password: false)
      # A troca derruba as outras sessões: se alguém estava dentro com a senha antiga, sai.
      # A sessão de quem trocou é recriada logo em seguida, senão ele se derrubaria sozinho.
      Audit.record("password.changed", request:)
      Current.user.revoke_sessions!
      start_new_session_for(Current.user)
      redirect_to root_path, notice: "Senha alterada."
    else
      @user = Current.user
      render :edit, status: :unprocessable_entity
    end
  end
end
