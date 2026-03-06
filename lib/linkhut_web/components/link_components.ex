defmodule LinkhutWeb.LinkComponents do
  @moduledoc """
  Provides UI components for Link pages.
  """
  use LinkhutWeb, :html

  alias LinkhutWeb.Router.Helpers, as: Routes

  @doc """
  Translates a link field error, rendering an "Edit the existing entry"
  link when the URL has already been saved.

  Falls back to `CoreComponents.translate_error/1` for all other errors.
  """
  def translate_link_error({_msg, opts} = error) do
    if opts[:constraint_name] == "links_url_user_id_index" do
      edit_path = Routes.link_path(LinkhutWeb.Endpoint, :edit, url: opts[:field_value])
      translated = Gettext.dgettext(LinkhutWeb.Gettext, "errors", elem(error, 0), opts)
      assigns = %{msg: translated, edit_path: edit_path}

      ~H"""
      {@msg} <a href={@edit_path}>{gettext("Edit the existing entry")}</a>
      """
    else
      LinkhutWeb.CoreComponents.translate_error(error)
    end
  end
end
