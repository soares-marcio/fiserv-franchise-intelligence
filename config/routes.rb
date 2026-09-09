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
  # Lançamentos diários de um EC, carregados sob demanda no modal da tela de subcanal.
  get "reports/sub_channels/:id/daily/:establishment_id", to: "reports#sub_channel_daily",
    as: :sub_channel_daily_report
  # Clientes que venderam num dia do calendário, carregados sob demanda no modal do ritmo.
  get "reports/weekly/day/:day", to: "reports#weekly_day", as: :weekly_day_report
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
