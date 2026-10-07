Rails.application.routes.draw do
  resource :session, only: %i[new create destroy]
  # Telas do caminho de entrada: o desafio do segundo fator, a inscrição dele e a troca da
  # própria senha (obrigatória no primeiro acesso).
  get "mfa", to: "mfa#show", as: :mfa
  post "mfa", to: "mfa#create"
  resource :mfa_enrollment, only: %i[show create], controller: "mfa_enrollments"
  resource :password, only: %i[edit update]
  # O nome da organização, dado pelo administrador dela no primeiro acesso.
  resource :organization, only: %i[edit update]
  get "up" => "rails/health#show", as: :rails_health_check

  root "reports#index"
  resources :reports, only: :index do
    collection do
      get :stalled
      get :weekly
      get :three_months
      get :recurring
      get :indicators
    end
  end
  get "reports/sub_channels/:id", to: "reports#sub_channel", as: :sub_channel_report
  # Lançamentos diários de um cliente, somando os ECs dele, carregados sob demanda no modal
  # da tela de subcanal. O :company_id é a uuid da empresa, não o CNPJ: o filtro de log
  # esconde :cnpj dos parâmetros, mas não do caminho da URL.
  get "reports/sub_channels/:id/daily/:company_id", to: "reports#sub_channel_daily",
    as: :sub_channel_daily_report
  # Clientes que venderam num dia do calendário, carregados sob demanda no modal do ritmo.
  get "reports/weekly/day/:day", to: "reports#weekly_day", as: :weekly_day_report
  get "reports/three_months/:id", to: "reports#three_months_sub_channel", as: :three_months_sub_channel_report
  # Apagar Master e MIC é marcar: a tela confirma com o nome digitado, e só a plataforma
  # restaura (ver platform/channels e platform/sub_channels).
  resources :channels, only: [] do
    resource :deletion, only: %i[new create], controller: "channel_deletions"
  end
  resources :sub_channels, only: [] do
    resource :deletion, only: %i[new create], controller: "sub_channel_deletions"
  end

  resources :import_batches, only: %i[index show create destroy] do
    member do
      patch :update_cutoff
      post :reprocess
      # Revisão de lote em quarentena: a tela mostra o que muda antes de a decisão ser
      # tomada; aprovar é o que consolida.
      get :review
      post :approve
      post :reject
    end
    # Liberação nominal do arquivo: quem mais, além de quem enviou, pode vê-lo e baixá-lo.
    resources :batch_grants, only: %i[create destroy]
  end
  resources :establishments, only: %i[index show]
  # Anotação do cliente, editada de duas telas. O :id é a uuid da empresa, não o CNPJ: o
  # filtro de log esconde :cnpj dos parâmetros, mas não do caminho da URL.
  patch "companies/:id/note", to: "company_notes#update", as: :company_note
  get "companies/:id/note/edit", to: "company_notes#edit", as: :edit_company_note
  # Substitui a rota de upload direto do Active Storage, que o Trix usa para os anexos da
  # anotação. Declarada aqui, tem precedência sobre a do engine — que ficaria aberta a
  # qualquer tipo e tamanho.
  post "/rails/active_storage/direct_uploads", to: "note_attachments#create"
  resource :metabase, only: :show, controller: "metabase"
  get "search", to: "search#index", as: :search
  # Trilha de auditoria: leitura de administração.
  resources :audit_events, only: :index
  # Administração de acessos: convite, permissões, escopo e liberação de lotes.
  resources :users, except: %i[destroy] do
    member do
      post :reset_mfa
      post :deactivate
      post :reactivate
    end
  end

  # A plataforma: cria organizações e o administrador de cada uma, vê quem existe e presta
  # suporte às contas — e não abre tela de dado nenhuma.
  namespace :platform do
    resources :channels, only: [] do
      member { post :restore }
    end
    resources :sub_channels, only: [] do
      member { post :restore }
    end
    resources :organizations, only: %i[index show new create] do
      resources :admins, only: %i[new create], controller: "organization_admins"
      member do
        get :history
        patch :rename
        post :suspend
        post :reactivate
      end
    end
    resources :users, only: :show do
      member do
        post :reset_mfa
        post :deactivate
        post :reactivate
      end
    end
  end
end
