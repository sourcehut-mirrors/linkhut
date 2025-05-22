defmodule LinkhutWeb.Settings.ProfileController do
  use LinkhutWeb, :controller

  alias Linkhut.Accounts

  def show(conn, _) do
    user = conn.assigns[:current_user]
    changeset = Accounts.change_user(user)

    render(conn, :profile,
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

    render(conn, :delete_account, changeset: Accounts.change_user(user))
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
        |> render(:delete_account, changeset: changeset)
    end
  end

  defp update(conn, user, params) when not is_nil(user) do
    with {:ok, user} <- Accounts.update_profile(user, params),
         {:ok, user, current_email} <- Accounts.apply_email_change(user, params) do
      Accounts.deliver_update_email_instructions(
        user,
        current_email,
        &url(~p"/_/confirm-email/#{&1}")
      )

      conn
      |> put_flash(:info, "Profile updated")
      |> redirect(to: Routes.profile_path(conn, :show))
    else
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Profile updated")
        |> redirect(to: Routes.profile_path(conn, :show))

      {:error, changeset} ->
        conn
        |> render(:profile,
          user: user,
          changeset: changeset
        )
    end
  end
end
