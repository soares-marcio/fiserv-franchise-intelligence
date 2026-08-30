Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "reports#index"
  resources :reports, only: :index do
    collection do
      get :stalled
      get :weekly
    end
  end
  resources :import_batches, only: %i[index show create] do
    member do
      patch :update_cutoff
      post :reprocess
    end
  end
  resources :establishments, only: %i[index new create show]
  resource :metabase, only: :show, controller: "metabase"
end
