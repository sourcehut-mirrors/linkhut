defmodule LinkhutWeb.Api.IFTT.ActionsView do
  @moduledoc false
  use LinkhutWeb, :view

  def render("success.json", %{id: id, url: url}) do
    %{
      data: [
        %{
          meta: %{
            id: id,
            url: url
          }
        }
      ]
    }
  end

  def render("error.json", %{message: message}) do
    %{
      errors: [
        %{
          status: "SKIP",
          message: message
        }
      ]
    }
  end

  def render("error.json", %{errors: errors}) do
    render("error.json", %{message: error_message(errors)})
  end

  defp error_message(errors) do
    errors
    |> Enum.map(fn {field, errors} ->
      "#{Phoenix.Naming.humanize(field)}: #{Enum.join(errors, ", ")}"
    end)
    |> Enum.join(". ")
  end
end
