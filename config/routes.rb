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

  # Webhook Pagomedios (POST servidor). El segmento webhook_secret valida el remitente.
  match "payments/webhook(/:webhook_secret)", to: "payments#webhook", via: [ :get, :post ], as: :payments_webhook

  # Funnel público de inscripción a cursos (sin login ni token firmado).
  # Rutas propias: el webhook y el retorno NO se comparten con el flujo de deudas (ADR-011).
  scope "inscripcion", as: :inscripcion do
    get  "cursos/:codigo", to: "inscripcion/checkout#show", as: :curso
    post "checkout", to: "inscripcion/checkout#create", as: :checkout
    get  "resultado", to: "inscripcion/checkout#result", as: :resultado
    match "webhook(/:webhook_secret)", to: "inscripcion/webhooks#create", via: [ :get, :post ], as: :webhook
  end

  namespace :admin do
    resources :payments, only: [ :index, :show ], path: "pagos"
    resources :orders, only: [ :index, :show ], path: "ordenes"
  end

  # Defines the root path route ("/")
  # root "posts#index"
end
