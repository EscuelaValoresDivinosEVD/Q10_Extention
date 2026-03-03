Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Pagomedios: formulario de pago y generación de enlace
  root "payments#new"
  get "pagar", to: "payments#new", as: :payments
  post "pagar", to: "payments#create"

  # Defines the root path route ("/")
  # root "posts#index"
end
