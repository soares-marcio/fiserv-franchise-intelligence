class ApplicationController < ActionController::Base
  include Authentication
  include Pundit::Authorization


  # Duas pendências que valem mais que qualquer tela: senha provisória por trocar e segundo
  # fator por inscrever. Ficam aqui, na base, porque um controller novo que esqueça de
  # declará-las nasceria fora da regra.
  before_action :require_password_change
  before_action :require_mfa_enrollment

  # A guarda que faz a diferença entre "negar por padrão" escrito e praticado: ação que
  # esquecer de autorizar falha no teste, em vez de servir o dado calada. Fica na base, que
  # não tem ação própria — declarada por controller, um controller novo nasceria de fora.
  after_action :verify_authorized

  rescue_from Pundit::NotAuthorizedError, with: :forbidden

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Idade do arquivo e do dado, uma consulta por requisição: o selo do cabeçalho está em
  # toda página e a tela de importação repete a mesma leitura no painel por master.
  helper_method :file_freshness

  def file_freshness
    @file_freshness ||= FileFreshness.new
  end

  private

  # 403 renderizado, nunca redirect_back: voltar para a página anterior com um destino vindo
  # do cabeçalho é redirecionamento aberto, que o Brakeman acusa e com razão.
  def forbidden
    respond_to do |format|
      format.html { render "errors/forbidden", status: :forbidden }
      format.any { head :forbidden }
    end
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
end
