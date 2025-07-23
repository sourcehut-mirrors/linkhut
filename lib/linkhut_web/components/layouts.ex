defmodule LinkhutWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality.
  """
  use LinkhutWeb, :html
  use Phoenix.HTML
  use PhoenixHtmlSanitizer, :basic_html
  use Gettext, backend: LinkhutWeb.Gettext

  alias LinkhutWeb.Router.Helpers, as: Routes

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton, namely HTML headers and other static content.
  embed_templates "layouts/*"

  @ex_doc_version Mix.Project.config()[:version]

  @doc """
  Returns the linkhut version.
  """
  @spec version :: String.t()
  def version, do: @ex_doc_version
end
