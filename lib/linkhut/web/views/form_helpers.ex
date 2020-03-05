defmodule Linkhut.Web.FormHelpers do
  @moduledoc """
  Conveniences for translating and building error messages when validating forms
  """
  use Phoenix.HTML

  @doc """
  Wraps a form input in a div that carries information on why it failed validation
  """
  def input(form, field, opts \\ []) do
    name = Keyword.get(opts, :name, humanize(field))
    type = Keyword.get(opts, :type, input_type(form, field))

    label = label(form, field, name)
    input = apply(Phoenix.HTML.Form, type, [form, field, opts])

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
                content_tag(:li, translate_error(error), class: "invalid")
              end)
            )
          ]
        end
      )
    else
      html_escape([fun.()])
    end
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate "is invalid" in the "errors" domain
    #     dgettext("errors", "is invalid")
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # Because the error messages we show in our forms and APIs
    # are defined inside Ecto, we need to translate them dynamically.
    # This requires us to call the Gettext module passing our gettext
    # backend as first argument.
    #
    # Note we use the "errors" domain, which means translations
    # should be written to the errors.po file. The :count option is
    # set by Ecto and indicates we should also apply plural rules.
    if count = opts[:count] do
      Gettext.dngettext(Linkhut.Web.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(Linkhut.Web.Gettext, "errors", msg, opts)
    end
  end
end
