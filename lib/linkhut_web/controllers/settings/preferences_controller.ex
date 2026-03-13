defmodule LinkhutWeb.Settings.PreferencesController do
  use LinkhutWeb, :controller

  alias Linkhut.Accounts.Preferences

  def show(conn, _) do
    preference = conn.assigns[:preferences]
    changeset = Preferences.change(preference)

    render(conn, :show, changeset: changeset)
  end

  def update(conn, %{"user_preference" => params}) do
    user = conn.assigns[:current_user]

    case Preferences.upsert(user, params) do
      {:ok, _preference} ->
        conn
        |> put_flash(:info, gettext("Preferences updated"))
        |> redirect(to: ~p"/_/preferences")

      {:error, changeset} ->
        conn
        |> render(:show, changeset: changeset)
    end
  end
end
