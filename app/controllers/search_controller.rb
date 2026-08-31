class SearchController < ApplicationController
  # Dentro do diálogo só o frame interessa; acessada direto, a página ganha a casca.
  layout -> { turbo_frame_request? ? false : "application" }

  def index
    @search = GlobalSearch.new(params[:q])
  end
end
