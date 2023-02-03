defmodule LinkhutWeb.FormHelpers do
  @moduledoc """
  Conveniences for translating and building error messages when validating forms
  """
  use Phoenix.HTML
  alias Phoenix.HTML.Form
  alias LinkhutWeb.ErrorHelpers

  @doc """
  Wraps a form input in a div that carries information on why it failed validation
  """
  def input(form, field, opts \\ []) do
    name = Keyword.get(opts, :label, humanize(field))
    {type, opts} = Keyword.pop(opts, :type, input_type(form, field))
    opts = Keyword.put_new(opts, :value, Form.input_value(form, field) |> value_to_string())

    label = label(form, field, name)
    input = apply(Form, type, [form, field, opts])

    if type == :checkbox do
      generate_input(form, field, fn -> [input, label] end)
    else
      generate_input(form, field, fn -> [label, input] end)
    end
  end

  defp generate_input(form, field, fun) do
    errors = Keyword.get_values(form.errors, field)

    if length(errors) > 0 do
      html_escape(
        content_tag(:div, class: "invalid") do
          [
            fun.(),
            content_tag(
              :ul,
              Enum.map(errors, fn error ->
                content_tag(:li, ErrorHelpers.translate_error(error), class: "invalid")
              end)
            )
          ]
        end
      )
    else
      html_escape([fun.()])
    end
  end

  defp value_to_string(list) when is_list(list), do: Enum.join(list, " ")
  defp value_to_string(value), do: value
end
