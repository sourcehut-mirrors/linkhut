defmodule LinkhutWeb.Settings.ProfileController do
  use LinkhutWeb, :controller

  alias Linkhut.Accounts

  def show(conn, _) do
    user = conn.assigns[:current_user]
    changeset = Accounts.change_user(user)

    render(conn, :show,
      user: user,
      changeset: changeset
    )
  end

  def update(conn, %{"user" => user_params}) do
    conn
    |> update(conn.assigns[:current_user], user_params)
  end

  def remove(conn, _) do
    user = conn.assigns[:current_user]

    render(conn, :delete, changeset: Accounts.change_user(user))
  end

  def delete(conn, %{"delete_form" => delete_form}) do
    user = conn.assigns[:current_user]

    case Accounts.delete_user(user, delete_form) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Deleted account for #{user.username}")
        |> configure_session(drop: true)
        |> redirect(to: "/")

      {:error, changeset} ->
        conn
        |> render(:delete, changeset: changeset)
    end
  end

  defp update(conn, %Accounts.User{} = user, params) do
    with {:ok, user} <- Accounts.update_profile(user, params),
         {:ok, user, current_email} <- Accounts.apply_email_change(user, params) do
      Accounts.deliver_update_email_instructions(
        user,
        current_email,
        &url(~p"/_/confirm-email/#{&1}")
      )

      conn
      |> put_flash(:info, "Profile updated")
      |> redirect(to: ~p"/_/profile")
    else
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Profile updated")
        |> redirect(to: ~p"/_/profile")

      {:error, changeset} ->
        conn
        |> render(:show,
          user: user,
          changeset: changeset
        )
    end
  end
end
