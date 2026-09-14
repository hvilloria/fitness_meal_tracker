Rails.application.routes.draw do
  get "sign_in", to: "sessions#new"
  post "/auth/:provider", to: "sessions#passthru", as: :auth_request
  get "/auth/:provider/callback", to: "sessions#create", constraints: { provider: /google_oauth2/ }
  get "/auth/failure", to: "sessions#failure"
  delete "sign_out", to: "sessions#destroy"

  get "up" => "rails/health#show", as: :rails_health_check

  resource :goal, only: %i[edit update]
  resources :foods
  resources :entries, only: %i[new create destroy]

  root "days#show"
end
