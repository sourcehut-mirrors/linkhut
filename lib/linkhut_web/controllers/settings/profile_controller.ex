defmodule LinkhutWeb.Settings.ProfileController do
  use LinkhutWeb, :controller

  alias Linkhut.Accounts

  def show(conn, _) do
    user = conn.assigns[:current_user]
    changeset = Accounts.change_user(user)

    render(conn, :profile,
      user: user,
      changeset: changeset,
      current_email_unconfirmed?: Accounts.current_email_unconfirmed?(user)
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
        |> redirect(to: "/")
        |> configure_session(drop: true)

      {:error, changeset} ->
        conn
        |> render(:delete_account, changeset: changeset)
    end
  end

  defp update(conn, user, params) when not is_nil(user) do
    case Accounts.update_user(user, params) do
      {:ok, user} ->
        if Accounts.pending_email_change?(user) != nil do
          Accounts.deliver_update_email_instructions(
            user,
            &url(~p"/_/confirm?#{%{token: Base.url_encode64(&1)}}")
          )
        end

        conn
        |> put_flash(:info, "Profile updated")
        |> redirect(to: Routes.profile_path(conn, :show))

      {:error, changeset} ->
        conn
        |> render(:profile,
          user: user,
          changeset: changeset,
          current_email_unconfirmed?: Accounts.current_email_unconfirmed?(user)
        )
    end
  end

  defp update(conn, user, _params) when is_nil(user) do
    conn
    |> put_flash(:error, "No access")
    |> redirect(to: Routes.link_path(conn, :show))
  end
end
