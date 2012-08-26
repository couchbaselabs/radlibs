Radlibs::Application.routes.draw do


  get "radministration/index"

  match '/auth/:provider/callback' => 'user#authenticate'

  controller :user do
    get '/create' => :create_radlib
    get "/my_radlibs" => :my_radlibs
    get '/logout' => :logout
    get '/u/:uid' => :profile
    get '/profile_not_found' => :profile_not_found

    post '/save_radlib' => :save_created_radlib
    post '/fill_radlib' => :save_filled_radlib
    post '/like_radlib_fillin' => :like_radlib_fillin
    post '/comment_on_radlib_fillin' => :comment_on_radlib_fillin
  end

  controller :radlibs_app do
    get "/random" => :random_radlib
    get '/r/:radlib_id' => :view_radlib
    get '/update_header_after_authentication' => :update_header_after_authentication
    get '/radlib_not_found' => :radlib_not_found
    get '/toilet_flush' => :delete_all_docs_and_sessions
  end

  controller :radministration do
    get '/radmin' => :index
    get '/users' => :users
    get '/radlibs' => :radlibs
    get '/app_settings' => :application_settings
  end

  controller :api do
    post '/api/lookup_word' => :lookup_word
    post '/api/lookup_parts_of_speech' => :lookup_parts_of_speech
    post '/api/lookup_fb_friend'

  end
  #root :to => redirect('/login') #:to => 'user#login'
  root :to => 'radlibs_app#index'




  # LAST Route to push user to custom 404 for non-matching page requests
  match "*path" => 'application#raise_404'



  # The priority is based upon order of creation:
  # first created -> highest priority.

  # Sample of regular route:
  #   match 'products/:id' => 'catalog#view'
  # Keep in mind you can assign values other than :controller and :action

  # Sample of named route:
  #   match 'products/:id/purchase' => 'catalog#purchase', :as => :purchase
  # This route can be invoked with purchase_url(:id => product.id)

  # Sample resource route (maps HTTP verbs to controller actions automatically):
  #   resources :products

  # Sample resource route with options:
  #   resources :products do
  #     member do
  #       get 'short'
  #       post 'toggle'
  #     end
  #
  #     collection do
  #       get 'sold'
  #     end
  #   end

  # Sample resource route with sub-resources:
  #   resources :products do
  #     resources :comments, :sales
  #     resource :seller
  #   end

  # Sample resource route with more complex sub-resources
  #   resources :products do
  #     resources :comments
  #     resources :sales do
  #       get 'recent', :on => :collection
  #     end
  #   end

  # Sample resource route within a namespace:
  #   namespace :admin do
  #     # Directs /admin/products/* to Admin::ProductsController
  #     # (app/controllers/admin/products_controller.rb)
  #     resources :products
  #   end

  # You can have the root of your site routed with "root"
  # just remember to delete public/index.html.
  # root :to => 'welcome#index'

  # See how all your routes lay out with "rake routes"

  # This is a legacy wild controller route that's not recommended for RESTful applications.
  # Note: This route will make all actions in every controller accessible via GET requests.
  # match ':controller(/:action(/:id))(.:format)'
end
