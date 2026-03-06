defmodule LinkhutWeb.Api.IFTTT.ActionsJSON do
  @moduledoc false

  def success(%{id: id, url: url}) do
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
