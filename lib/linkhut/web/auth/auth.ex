defmodule Linkhut.Web.Auth do
  import Argon2, only: [verify_pass: 2, no_user_verify: 1]
  alias Linkhut.Model.User
  alias Linkhut.Repo

  def login(conn, user) do
    conn
    |> Linkhut.Web.Auth.Guardian.Plug.sign_in(user, %{"typ" => "access"})
  end

  def login_by_email_and_pass(conn, email, given_pass) do
    user = Repo.get_by(User, email: email)

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
