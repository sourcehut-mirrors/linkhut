defmodule LinkhutWeb.Router do
  use LinkhutWeb, :router
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

  pipeline :feed do
    plug :accepts, ["xml"]
  end

  scope "/_/feed", LinkhutWeb, as: :feed do
    pipe_through :feed

    get "/", LinkController, :show, as: :recent
    get "/~:username", LinkController, :show, as: :user
    get "/~:username/*tags", LinkController, :show, as: :user_tags
    get "/*tags", LinkController, :show
  end

  scope "/_", LinkhutWeb do
    pipe_through [:browser, :ensure_auth]

    get "/import", Settings.ImportController, :show
    post "/import", Settings.ImportController, :upload

    get "/export", Settings.ExportController, :show
    get "/download", Settings.ExportController, :download

    get "/misc", Settings.MiscController, :show

    get "/profile", Settings.ProfileController, :show
    put "/profile", Settings.ProfileController, :update

    get "/add", LinkController, :new
    post "/add", LinkController, :insert

    get "/edit", LinkController, :edit
    put "/edit", LinkController, :update

    get "/delete", LinkController, :remove
    put "/delete", LinkController, :delete

    delete "/logout", Auth.SessionController, :delete
  end

  # Enables LiveDashboard only for development
  if Mix.env() == :dev do
    scope "/_/admin" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: LinkhutWeb.Telemetry
    end
  end

  scope "/_", LinkhutWeb do
    pipe_through :browser

    get "/register", Auth.RegistrationController, :new
    post "/register", Auth.RegistrationController, :create

    get "/login", Auth.SessionController, :new
    post "/login", Auth.SessionController, :create
  end

  scope "/", LinkhutWeb do
    pipe_through :browser

    get "/", LinkController, :show, as: :recent
    get "/~:username", LinkController, :show, as: :user
    get "/~:username/*tags", LinkController, :show, as: :user_tags
    get "/*tags", LinkController, :show
  end
end
