defmodule LinkhutWeb.Router do
  use LinkhutWeb, :router
  use PhoenixOauth2Provider.Router, otp_app: :linkhut
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug LinkhutWeb.Plugs.SetCurrentUser
  end

  pipeline :ensure_auth do
    plug LinkhutWeb.Plugs.EnsureAuth
  end

  pipeline :token_auth do
    plug LinkhutWeb.Plugs.VerifyTokenAuth
  end

  pipeline :feed do
    plug :accepts, ["xml"]
  end

  pipeline :api do
    plug :accepts, ["xml", "json"]
  end

  scope "/_/v1/" do
    pipe_through :api

    oauth_api_routes()
  end

  scope "/_/v1/", LinkhutWeb.Api, as: :api do
    pipe_through [:api, :token_auth]

    get "/posts/update", PostsController, :update
    get "/posts/add", PostsController, :add
    get "/posts/delete", PostsController, :delete
    get "/posts/get", PostsController, :get
    get "/posts/recent", PostsController, :recent
    get "/posts/dates", PostsController, :dates
    get "/posts/all", PostsController, :all
    get "/posts/suggest", PostsController, :suggest

    get "/tags/get", TagsController, :get
    get "/tags/delete", TagsController, :delete
    get "/tags/rename", TagsController, :rename
  end

  scope "/_/ifttt/v1/", LinkhutWeb.Api.IFTT, as: :ifttt do
    pipe_through [:api, :token_auth]

    get "/user/info", UserController, :info

    post "/triggers/new_public_link", TriggersController, :new_public_link
    post "/triggers/new_public_link_tagged", TriggersController, :new_public_link_tagged
  end

  scope "/_/feed", LinkhutWeb, as: :feed do
    pipe_through :feed

    get "/", LinkController, :show
    get "/~:username", LinkController, :show, as: :user
    get "/~:username/-:url", LinkController, :show, as: :user_bookmark
    get "/~:username/-:url/*tags", LinkController, :show, as: :user_bookmark_tags
    get "/~:username/*tags", LinkController, :show, as: :user_tags
    get "/-:url", LinkController, :show, as: :bookmark
    get "/-:url/*tags", LinkController, :show, as: :bookmark_tags
    get "/*tags", LinkController, :show, as: :tags
  end

  scope "/_", LinkhutWeb.Settings do
    pipe_through [:browser, :ensure_auth]

    get "/import", ImportController, :show
    post "/import", ImportController, :upload

    get "/export", ExportController, :show
    get "/download", ExportController, :download

    get "/misc", MiscController, :show
    get "/profile", ProfileController, :show
    put "/profile", ProfileController, :update
  end

  scope "/_", LinkhutWeb do
    pipe_through [:browser, :ensure_auth]

    get "/add", LinkController, :new
    post "/add", LinkController, :insert

    get "/edit", LinkController, :edit
    put "/edit", LinkController, :update

    get "/delete", LinkController, :remove
    put "/delete", LinkController, :delete

    delete "/logout", Auth.SessionController, :delete
  end

  scope "/_/oauth", LinkhutWeb.Settings do
    pipe_through [:browser, :ensure_auth]

    get "/", OauthController, :show
    get "/personal-token", OauthController, :new_personal_token
    post "/personal-token", OauthController, :create_personal_token
    get "/personal-token/revoke/:id", OauthController, :revoke_token
    put "/personal-token/revoke/:id", OauthController, :revoke_token

    get "/register", OauthController, :new_application
    post "/register", OauthController, :create_application
    get "/registered", OauthController, :show_application
    get "/application/:uid/settings", OauthController, :edit_application
    put "/application/:uid/settings", OauthController, :update_application
    post "/application/delete/:uid", OauthController, :delete_application
    post "/revoke-tokens/:uid", OauthController, :revoke_application
    post "/reset-secret/:uid", OauthController, :reset_application

    get "/authorize", OauthController, :new_authorization
    post "/authorize", OauthController, :create_authorization
    delete "/authorize", OauthController, :delete_authorization
  end

  # Enables LiveDashboard only for development
  if Mix.env() == :dev do
    scope "/_/admin" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: LinkhutWeb.Telemetry, ecto_repos: [Linkhut.Repo]
    end
  end

  scope "/_", LinkhutWeb do
    pipe_through :browser

    get "/register", Auth.RegistrationController, :new
    post "/register", Auth.RegistrationController, :create

    get "/login", Auth.SessionController, :new
    post "/login", Auth.SessionController, :create
  end

  scope "/_", LinkhutWeb do
    pipe_through [:browser, :ensure_auth]
    get "/unread", LinkController, :unread, as: :unread
  end

  scope "/", LinkhutWeb do
    pipe_through :browser

    get "/", LinkController, :show
    get "/~:username", LinkController, :show, as: :user
    get "/~:username/-:url", LinkController, :show, as: :user_bookmark
    get "/~:username/-:url/*tags", LinkController, :show, as: :user_bookmark_tags
    get "/~:username/*tags", LinkController, :show, as: :user_tags
    get "/-:url", LinkController, :show, as: :bookmark
    get "/-:url/*tags", LinkController, :show, as: :bookmark_tags
    get "/*tags", LinkController, :show, as: :tags
  end
end
