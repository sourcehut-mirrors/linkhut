defmodule LinkhutWeb.Auth do
  import Argon2, only: [verify_pass: 2, no_user_verify: 1]
  alias Linkhut.Model.User
  alias Linkhut.Repo

  def login(conn, user) do
    conn
    |> LinkhutWeb.Auth.Guardian.Plug.sign_in(user, %{"typ" => "access"})
  end

  def login_by_username_and_pass(conn, username, given_pass) do
    user = Repo.get_by(User, username: username)

    cond do
      user && verify_pass(given_pass, user.password_hash) ->
        {:ok, login(conn, user)}

      user ->
        {:error, :unauthorized, conn}

      true ->
        no_user_verify(password: given_pass)
        {:error, :not_found, conn}
    end
  end
end
