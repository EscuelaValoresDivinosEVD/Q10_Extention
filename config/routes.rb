Rails.application.routes.draw do
  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Entrada estudiantes CLEV → luego flujo Pagomedios
  root "home#index"
  get "acceder", to: "home#acceder", as: :acceder_get
  post "acceder", to: "home#create", as: :acceder
  get "continuar", to: "q10_debts#show", as: :q10_continue

  # Pagomedios: formulario de pago y generación de enlace
  get "pagar", to: "payments#new", as: :payments
  post "pagar", to: "payments#create"
  get "pagos/resultado", to: "payments#show", as: :payment_result
  match "payments/return", to: "payments#return", via: [ :get, :post ], as: :payment_return

  # Webhook/callback Pagomedios (POST servidor; a veces el navegador también llega aquí)
  match "payments/webhook", to: "payments#webhook", via: [ :get, :post ], as: :payments_webhook

  namespace :admin do
    resources :payments, only: [ :index, :show ], path: "pagos"
  end

  # Defines the root path route ("/")
  # root "posts#index"
end
