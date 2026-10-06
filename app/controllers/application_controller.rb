class ApplicationController < ActionController::Base
  include Authentication
  include Pundit::Authorization


  # Duas pendências que valem mais que qualquer tela: senha provisória por trocar e segundo
  # fator por inscrever. Ficam aqui, na base, porque um controller novo que esqueça de
  # declará-las nasceria fora da regra.
  before_action :require_password_change
  before_action :require_mfa_enrollment
  before_action :require_organization_name

  # A guarda que faz a diferença entre "negar por padrão" escrito e praticado: ação que
  # esquecer de autorizar falha no teste, em vez de servir o dado calada. Fica na base, que
  # não tem ação própria — declarada por controller, um controller novo nasceria de fora.
  after_action :verify_authorized

  rescue_from Pundit::NotAuthorizedError, with: :forbidden
  # Formulário aberto até o token de segurança vencer: volta à tela de onde veio, com o
  # aviso, em vez da página solta do 422. Nada é gravado — o pedido foi recusado antes.
  rescue_from ActionController::InvalidAuthenticityToken, with: :expired_form

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Idade do arquivo e do dado, uma consulta por requisição: o selo do cabeçalho está em
  # toda página e a tela de importação repete a mesma leitura no painel por master.
  helper_method :file_freshness

  def file_freshness
    @file_freshness ||= FileFreshness.new(organization: Current.organization)
  end

  # Os itens do menu na ordem em que aparecem: a raiz leva ao primeiro que o ator tem.
  LANDING_SCREENS = [
    [ :report, :revenue?, :reports_path ], [ :report, :clover?, :stalled_reports_path ],
    [ :report, :weekly?, :weekly_reports_path ], [ :report, :three_months?, :three_months_reports_path ],
    [ :report, :recurring?, :recurring_reports_path ], [ :report, :indicators?, :indicators_reports_path ],
    [ :establishment, :index?, :establishments_path ], [ :import_batch, :index?, :import_batches_path ],
    [ :user, :index?, :users_path ]
  ].freeze

  private

  # nil quando o ator não tem tela nenhuma: aí a raiz responde o 403 de sempre.
  def landing_path
    screen = LANDING_SCREENS.find { |name, query, _| policy(name).public_send(query) }
    screen && public_send(screen.last)
  end

  # 403 renderizado, nunca redirect_back: voltar para a página anterior com um destino vindo
  # do cabeçalho é redirecionamento aberto, que o Brakeman acusa e com razão.
  def forbidden
    # Logo depois de entrar, o destino é a tela pedida antes do login, que pode ter perdido
    # a permissão no meio do caminho: entrar e ver "sem permissão" não diz nada à pessoa.
    if flash[:signed_in] && request.get? && (destination = landing_path) && destination != request.path
      return redirect_to(destination)
    end

    respond_to do |format|
      format.html { render "errors/forbidden", status: :forbidden, layout: "error" }
      format.any { head :forbidden }
    end
  end

  # Na entrada (senha ou código), a chave vencida quase sempre vem de outra aba: as abas
  # dividem o cookie, e a senha aceita numa troca a sessão e a chave dos formulários — de
  # propósito, contra fixação de sessão. Se a outra aba já entrou, esta entra também; se
  # está no meio, a mensagem diz o que houve (homologação de 06/10/2026).
  SIGN_IN_CONTROLLERS = %w[sessions mfa].freeze

  def expired_form
    return head(:unprocessable_entity) unless request.format.html?
    return expired_sign_in if SIGN_IN_CONTROLLERS.include?(controller_path)

    redirect_to expired_form_origin || root_path, status: :see_other,
      alert: "A página ficou aberta por muito tempo. Confira os dados e envie de novo."
  end

  def expired_sign_in
    return redirect_to(root_path, status: :see_other) if authenticated?

    redirect_to new_session_path, status: :see_other,
      alert: "Esta tela de entrada ficou desatualizada, provavelmente porque você entrou ou " \
        "saiu do portal em outra aba. Digite seus dados de novo."
  end

  # Só o caminho, e só se a origem for este mesmo portal: seguir o Referer inteiro seria
  # redirecionamento aberto.
  def expired_form_origin
    origin = URI.parse(request.referer.to_s)
    path = origin.request_uri if origin.is_a?(URI::HTTP) && origin.host == request.host
    path if safe_return_path?(path)
  rescue URI::InvalidURIError
    nil
  end

  def require_password_change
    return unless Current.user&.must_change_password?
    return if controller_name.in?(%w[passwords sessions])

    redirect_to edit_password_path, alert: "Defina sua senha antes de usar o portal."
  end

  def require_mfa_enrollment
    return if Current.user.nil? || Current.user.mfa_enabled?
    return if controller_name.in?(%w[mfa_enrollments sessions passwords])

    redirect_to mfa_enrollment_path, alert: "Cadastre o segundo fator antes de usar o portal."
  end

  # A terceira pendência, só do administrador da organização: a organização que a plataforma
  # criou não tem nome, e é ele quem dá. Colaborador não é redirecionado — não é dele para
  # nomear, e ficaria preso.
  def require_organization_name
    return unless Current.user&.organization_admin? && !Current.organization.named?
    return if controller_name.in?(%w[organizations sessions passwords mfa_enrollments mfa])

    redirect_to edit_organization_path, alert: "Dê um nome à sua organização antes de usar o portal."
  end
end
