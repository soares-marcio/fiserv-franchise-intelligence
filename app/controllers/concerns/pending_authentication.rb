# O intervalo entre "a senha está certa" e "entrou". Ele existe porque o segundo fator não
# pode ser pulado, e enquanto ele não for respondido **não há sessão no banco**: o estado
# vive num cookie cifrado de curta validade.
#
# É o que impede uma sessão meio-válida — alguém autenticado pela metade que algum ponto do
# código esqueça de conferir.
module PendingAuthentication
  extend ActiveSupport::Concern

  PENDING_LIMIT = 5.minutes

  private

  def start_pending_authentication(user)
    # O destino pedido antes do login viaja junto: o reset_session que protege contra
    # fixação de sessão apaga a sessão inteira, e com ela iria o caminho que a pessoa
    # tentou abrir.
    destino = session[:return_to_after_authenticating]
    reset_session
    cookies.encrypted[:pending_mfa] = {
      value: { user_id: user.id, at: Time.current.to_i, return_to: destino }.to_json,
      httponly: true, same_site: :lax, secure: request.ssl?, expires: PENDING_LIMIT.from_now
    }
  end

  def pending_return_to
    JSON.parse(cookies.encrypted[:pending_mfa].to_s)["return_to"]
  rescue JSON::ParserError, TypeError
    nil
  end

  def pending_user
    return @pending_user if defined?(@pending_user)

    @pending_user = begin
      dados = JSON.parse(cookies.encrypted[:pending_mfa].to_s)
      expirou = Time.at(dados["at"].to_i) < PENDING_LIMIT.ago
      expirou ? nil : User.active.find_by(id: dados["user_id"])
    rescue JSON::ParserError, TypeError
      nil
    end
  end

  def clear_pending_authentication
    cookies.delete(:pending_mfa)
  end
end
