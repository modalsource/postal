# frozen_string_literal: true

Rails.application.routes.draw do
  # Legacy API Routes
  match "/api/v1/send/message" => "legacy_api/send#message", via: [:get, :post, :patch, :put]
  match "/api/v1/send/raw" => "legacy_api/send#raw", via: [:get, :post, :patch, :put]
  match "/api/v1/messages/message" => "legacy_api/messages#message", via: [:get, :post, :patch, :put]
  match "/api/v1/messages/deliveries" => "legacy_api/messages#deliveries", via: [:get, :post, :patch, :put]

  scope "org/:org_permalink", as: "organization" do
    # Domain routes at organization level
    get "domains" => "domains#index", as: :domains
    post "domains" => "domains#create"
    get "domains/new" => "domains#new", as: :new_domain
    get "domains/:id" => "domains#show", as: :domain
    delete "domains/:id" => "domains#destroy"
    match "domains/:id/verify" => "domains#verify", via: [:get, :post], as: :verify_domain
    get "domains/:id/setup" => "domains#setup", as: :setup_domain
    post "domains/:id/check" => "domains#check", as: :check_domain
    get "domains/:id/edit_security" => "domains#edit_security", as: :edit_security_domain
    patch "domains/:id/update_security" => "domains#update_security", as: :update_security_domain
    post "domains/:id/check_mta_sts_policy" => "domains#check_mta_sts_policy", as: :check_mta_sts_policy_domain


    resources :servers, except: [:index] do
      resources :domains, only: [:index, :new, :create, :destroy] do
        member do
          match :verify, via: [:get, :post]
          get :setup
          post :check
          get :edit_security
          patch :update_security
          post :check_mta_sts_policy
        end
      end
      resources :track_domains do
        post :toggle_ssl, on: :member
        post :check, on: :member
      end
      resources :credentials
      resources :routes
      resources :http_endpoints
      resources :smtp_endpoints
      resources :address_endpoints
      resources :ip_pool_rules
      resources :messages do
        get :incoming, on: :collection
        get :outgoing, on: :collection
        get :held, on: :collection
        get :activity, on: :member
        get :plain, on: :member
        get :html, on: :member
        get :html_raw, on: :member
        get :attachments, on: :member
        get :headers, on: :member
        get :attachment, on: :member
        get :download, on: :member
        get :spam_checks, on: :member
        post :retry, on: :member
        post :cancel_hold, on: :member
        get :suppressions, on: :collection
        delete :remove_from_queue, on: :member
        get :deliveries, on: :member
      end
      resources :webhooks do
        get :history, on: :collection
        get "history/:uuid", on: :collection, action: "history_request", as: "history_request"
      end
      get :limits, on: :member
      get :retention, on: :member
      get :queue, on: :member
      get :spam, on: :member
      get :delete, on: :member
      get "help/outgoing" => "help#outgoing"
      get "help/incoming" => "help#incoming"
      get :advanced, on: :member
      post :suspend, on: :member
      post :unsuspend, on: :member
    end

    resources :ip_pool_rules
    resources :ip_pools, controller: "organization_ip_pools" do
      put :assignments, on: :collection
    end
    root "servers#index"
    get "settings" => "organizations#edit"
    patch "settings" => "organizations#update"
    get "delete" => "organizations#delete"
    delete "delete" => "organizations#destroy"
  end

  resources :organizations, except: [:index]
  resources :users
  resources :ip_pools do
    resources :ip_addresses
  end

  get "settings" => "user#edit"
  patch "settings" => "user#update"
  post "persist" => "sessions#persist"

  get "login" => "sessions#new"
  post "login" => "sessions#create"
  delete "logout" => "sessions#destroy"
  match "login/reset" => "sessions#begin_password_reset", :via => [:get, :post]
  match "login/reset/:token" => "sessions#finish_password_reset", :via => [:get, :post]

  if Postal::Config.oidc.enabled?
    get "auth/oidc/callback", to: "sessions#create_from_oidc"
  end

  get ".well-known/jwks.json" => "well_known#jwks"
  get ".well-known/mta-sts.txt" => "mta_sts#policy"

  get "ip" => "sessions#ip"

  root "organizations#index"
end
