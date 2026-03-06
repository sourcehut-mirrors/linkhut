defmodule LinkhutWeb.Api.IFTTT.UserJSON do
  @moduledoc false

  def info(%{user: user, url: url}) do
    %{data: %{name: user.username, id: "#{user.id}", url: url}}
  end
end
