Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Entrada estudiantes CLEV → luego flujo Pagomedios
  root "home#index"
  post "acceder", to: "home#create", as: :acceder

  # Pagomedios: formulario de pago y generación de enlace
  get "pagar", to: "payments#new", as: :payments
  post "pagar", to: "payments#create"

  # Webhook: Pagomedios envía POST aquí cuando el pago es autorizado/rechazado
  post "payments/webhook", to: "payments#webhook", as: :payments_webhook

  # Defines the root path route ("/")
  # root "posts#index"
end
