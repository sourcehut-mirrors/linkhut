defmodule LinkhutWeb.ErrorView do
  use LinkhutWeb, :view

  use Phoenix.HTML

  alias LinkhutWeb.Api.IFTTT.Errors.BadRequestError

  # If you want to customize a particular status code
  # for a certain format, you may uncomment below.
  # def render("500.html", _assigns) do
  #   "Internal Server Error"
  # end

  def render("404.xml", _assigns) do
    "Not Found"
  end

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

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.html" becomes
  # "Not Found".
  def template_not_found(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
