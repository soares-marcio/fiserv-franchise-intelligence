module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?, :current_user
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def current_user
      Current.session&.user
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    # Sessão expirada é sessão encerrada: some do banco e o cookie deixa de valer. Sem isso,
    # a linha ficaria viva para sempre e o limite de inatividade seria só decoração.
    def find_session_by_cookie
      return unless cookies.signed[:session_id]

      session = Session.find_by(id: cookies.signed[:session_id])
      return if session.nil?

      if session.expired? || !session.user.sign_in_allowed?
        session.destroy
        cookies.delete(:session_id)
        return
      end

      session.touch_activity
      session
    end

    def request_authentication
      # Só o caminho, nunca a URL inteira: com host e esquema, um valor forjado viraria
      # redirecionamento para fora do portal depois do login.
      session[:return_to_after_authenticating] = request.fullpath if safe_return_path?(request.fullpath)
      # O caminho vem das rotas da aplicação, e não do helper local: este concern também é
      # incluído nos controllers do Active Storage, que são de um engine e não enxergam
      # new_session_path.
      redirect_to Rails.application.routes.url_helpers.new_session_path
    end

    def after_authentication_url
      destino = session.delete(:return_to_after_authenticating)
      safe_return_path?(destino) ? destino : root_url
    end

    # Caminho interno é o que começa com uma barra só: "//exemplo.com" é URL de outro host
    # escrita como caminho, e o navegador a segue.
    def safe_return_path?(path)
      path.to_s.start_with?("/") && !path.to_s.start_with?("//")
    end

    def start_new_session_for(user)
      # Sessão nova, identificador novo: sem isto, quem conseguisse plantar um identificador
      # no navegador da vítima antes do login continuaria dono da sessão depois dele.
      reset_session
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip,
        last_active_at: Time.current).tap do |session|
        Current.session = session
        cookies.signed.permanent[:session_id] = {
          value: session.id, httponly: true, same_site: :lax,
          # A LAN serve HTTP puro: `secure` fixo faria o cookie nunca voltar em fiserv.bin.
          # O esquema vem de X-Forwarded-Proto quando há proxy, que é o caso do túnel.
          secure: request.ssl?
        }
      end
    end

    def terminate_session
      Current.session&.destroy
      cookies.delete(:session_id)
      reset_session
    end
end
