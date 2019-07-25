defmodule Linkhut.Web.Router do
  use Linkhut.Web, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug Linkhut.Web.Plugs.AuthenticationPlug
  end

  pipeline :ensure_auth do
    plug Guardian.Plug.EnsureAuthenticated
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", Linkhut.Web do
    pipe_through :browser

    get "/", LinkController, :index
    get "/~:username", LinkController, :show

    get "/register", Auth.RegistrationController, :new
    post "/register", Auth.RegistrationController, :create

    get "/login", Auth.SessionController, :new
    post "/login", Auth.SessionController, :create
  end

  scope "/", Linkhut.Web do
    pipe_through [:browser, :ensure_auth]

    get "/profile", Settings.ProfileController, :show
    put "/profile", Settings.ProfileController, :update

    get "/add", LinkController, :new
    post "/add", LinkController, :create

    delete "/logout", Auth.SessionController, :delete
  end

  # Other scopes may use custom stacks.
  # scope "/api", Linkhut.Web do
  #   pipe_through :api
  # end
end
