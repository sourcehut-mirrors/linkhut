defmodule LinkhutWeb.Settings.MiscController do
  use LinkhutWeb, :controller

  @moduledoc """
  Controller for miscellaneous settings
  """

  def show(conn, _) do
    render(conn, :misc)
  end
end
