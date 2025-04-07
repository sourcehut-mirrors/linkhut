defmodule LinkhutWeb.Auth.SessionController do
  use LinkhutWeb, :controller

  alias Linkhut.Accounts
  alias LinkhutWeb.UserAuth

  def new(conn, _) do
    username = get_in(conn.assigns, [:current_user, Access.key(:username)])
    form = Phoenix.Component.to_form(%{"username" => username}, as: "session")

    conn
    |> render(:login, form: form)
  end

  # username + password login
  def create(conn, %{"session" => %{"username" => username, "password" => pass}}) do
    case Accounts.authenticate_by_username_password(username, pass) do
      {:ok, user} ->
        conn
        |> UserAuth.log_in_user(user)

      {:error, :unauthorized} ->
        form = Phoenix.Component.to_form(%{"username" => username}, as: "session")

        conn
        |> put_flash(:error, "Wrong username/password")
        |> render(:login, form: form)
    end
  end

  def delete(conn, _) do
    conn
    |> UserAuth.log_out_user()
  end
end
