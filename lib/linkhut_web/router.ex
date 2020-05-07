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

  pipeline :feed do
    plug :accepts, ["xml"]
  end

  scope "/", LinkhutWeb do
    pipe_through :browser

    get "/", LinkController, :index
    get "/~:username", LinkController, :show

    get "/register", Auth.RegistrationController, :new
    post "/register", Auth.RegistrationController, :create

    get "/login", Auth.SessionController, :new
    post "/login", Auth.SessionController, :create
  end

  scope "/", LinkhutWeb do
    pipe_through [:browser, :ensure_auth]

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

  scope "/feed", LinkhutWeb, as: :feed do
    pipe_through :feed

    get "/~:username", FeedController, :show
  end

  # Enables LiveDashboard only for development
  if Mix.env() == :dev do
    scope "/" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: LinkhutWeb.Telemetry
    end
  end

  defp ensure_auth(conn, _) do
    if user = get_user(conn) do
      assign(conn, :current_user, user)
    else
      auth_error!(conn)
    end
  end

  defp get_user(conn) do
    case conn.assigns[:current_user] do
      nil ->
        fetch_user(conn)

      user ->
        user
    end
  end

  defp fetch_user(conn) do
    if user_id = get_session(conn, :user_id) do
      Linkhut.Accounts.get_user!(user_id)
    else
      nil
    end
  end

  defp auth_error!(conn) do
    conn
    |> store_path_in_session()
    |> put_flash(:error, "Login required")
    |> redirect(to: "/login")
    |> halt()
  end

  defp store_path_in_session(conn) do
    # Get HTTP method and url from conn
    method = conn.method
    path = conn.request_path

    # If conditions apply store path in session, else return conn unmodified
    case {method, String.match?(path, ~r/^\/(add)$/)} do
      {"GET", true} ->
        put_session(conn, :login_redirect_path, path)

      {_, _} ->
        conn
    end
  end
end
