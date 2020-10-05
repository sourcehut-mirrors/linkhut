defmodule LinkhutWeb.Settings.MiscController do
  use LinkhutWeb, :controller

  @moduledoc """
  Controller for miscellaneous settings
  """
  plug :put_view, LinkhutWeb.SettingsView

  def show(conn, _) do
    render(conn, "misc.html")
  end
end
