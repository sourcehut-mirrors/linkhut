defmodule LinkhutWeb.ErrorJSON do
  @moduledoc false

  alias LinkhutWeb.Api.IFTTT.Errors.BadRequestError

  def render("400.json", %{conn: conn}) do
    case conn.assigns.reason do
      %BadRequestError{message: message} ->
        %{
          errors: [
            %{
              status: "SKIP",
              message: message
            }
          ]
        }

      _ ->
        %{errors: [%{message: "Bad Request"}]}
    end
  end

  def render(template, _assigns) do
    %{errors: [%{message: Phoenix.Controller.status_message_from_template(template)}]}
  end
end
