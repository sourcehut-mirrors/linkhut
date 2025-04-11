defmodule LinkhutWeb.Settings.SecurityController do
  use LinkhutWeb, :controller

  @moduledoc """
  Controller for security settings
  """

  import Phoenix.Component
  alias Linkhut.Accounts

  def show(conn, _) do
    email = get_in(conn.assigns, [:current_user]) |> Accounts.get_email()
    form = to_form(%{"email" => email})

    conn
    |> render(:security, email: email, form: form)
  end
end
