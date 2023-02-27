defmodule LinkhutWeb.Settings.AdminController do
  use LinkhutWeb, :controller

  @moduledoc """
  Controller for admin operations
  """
  plug :put_view, LinkhutWeb.SettingsView

  def show(conn, _) do
    render(conn, "admin.html")
  end
end
