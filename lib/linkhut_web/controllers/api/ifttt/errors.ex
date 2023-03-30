defmodule LinkhutWeb.Api.IFTTT.Errors do
  @moduledoc false
  defmodule BadRequestError do
    defexception [:message, plug_status: 400]

    @impl true
    def exception(msg) when is_binary(msg) do
      %BadRequestError{message: msg}
    end

    @impl true
    def exception(errors) when is_list(errors), do: exception(error_message(errors))

    defp error_message(errors) do
      errors
      |> Enum.map(fn
        {field, errors} ->
          "#{Phoenix.Naming.humanize(field)}: #{Enum.join(errors, ", ")}"

        error ->
          error
      end)
      |> Enum.join(". ")
    end
  end
end
