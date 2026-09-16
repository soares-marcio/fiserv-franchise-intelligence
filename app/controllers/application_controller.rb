class ApplicationController < ActionController::Base
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
end
