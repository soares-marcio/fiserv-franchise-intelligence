Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "reports#index"
  resources :reports, only: :index do
    collection do
      get :stalled
      get :weekly
      get :three_months
      get :recurring
    end
  end
  get "reports/sub_channels/:id", to: "reports#sub_channel", as: :sub_channel_report
  get "reports/three_months/:id", to: "reports#three_months_sub_channel", as: :three_months_sub_channel_report
  resources :import_batches, only: %i[index show create destroy] do
    member do
      patch :update_cutoff
      post :reprocess
    end
  end
  resources :establishments, only: %i[index show]
  resource :metabase, only: :show, controller: "metabase"
  get "search", to: "search#index", as: :search
end
