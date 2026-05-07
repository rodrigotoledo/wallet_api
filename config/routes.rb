Rails.application.routes.draw do
  root "rails/health#show"

  get "session/new", to: "sessions#new", as: :new_session
  resource :session
  resources :registrations, only: :create
  resources :passwords, param: :token

  namespace :api do
    namespace :v1 do
      resource :profile, only: :show
      resources :deposits, only: :create
      resources :withdrawals, only: :create
      resources :transfers, only: :create
      resources :tenant_users, only: :index
      resources :batch_deposits, only: %i[create show]
      resources :transactions, only: :index
    end
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
