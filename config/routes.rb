Rails.application.routes.draw do
  get "health", to: "health#show"
  namespace :api do
    namespace :v1 do
      resources :calls, only: %i[index show], param: :call_id
    end
  end
end
