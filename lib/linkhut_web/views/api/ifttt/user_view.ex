defmodule LinkhutWeb.Api.IFTT.UserView do
  @moduledoc false
  use LinkhutWeb, :view

  def render("info.json", %{user: user, url: url}) do
    %{data: %{name: user.username, id: user.id, url: url}}
  end
end
