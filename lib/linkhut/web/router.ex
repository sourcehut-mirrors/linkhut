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

    get "/", PageController, :index
    resources "/users", UserController, only: [:new, :create]
    resources "/sessions", SessionController, only: [:new, :create, :delete]
  end

  scope "/", Linkhut.Web do
    pipe_through [:browser, :ensure_auth]

    resources "/users", UserController, only: [:show, :index, :update]
  end

  # Other scopes may use custom stacks.
  # scope "/api", Linkhut.Web do
  #   pipe_through :api
  # end
end
