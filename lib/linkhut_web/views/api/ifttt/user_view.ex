defmodule LinkhutWeb.Api.IFTTView do
  @moduledoc false
  use LinkhutWeb, :view

  def render("user_info.json", %{name: name, id: id, url: url}) do
    %{data: %{name: name, id: id, url: url}}
  end
end