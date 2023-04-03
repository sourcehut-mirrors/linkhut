defmodule LinkhutWeb.Api.IFTTT.ActionsView do
  @moduledoc false
  use LinkhutWeb, :view

  def render("success.json", %{id: id, url: url}) do
    %{
      data: [
        %{
          id: id,
          url: url
        }
      ]
    }
  end
end
