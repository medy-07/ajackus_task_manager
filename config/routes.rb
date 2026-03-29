Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :tasks, only: [:index, :show, :create] do
        member do
          patch :cancel
        end
      end
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
