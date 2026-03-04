defmodule LinkhutWeb.Settings.ExportHTML do
  @moduledoc """
  Renders bookmark export formats.

  Uses `EEx.function_from_file/4` rather than `embed_templates` because the
  Netscape bookmark format is not valid HTML/HEEx.
  """

  require EEx

  EEx.function_from_file(
    :def,
    :bookmarks_netscape,
    Path.join(__DIR__, "export_html/bookmarks.netscape.eex"),
    [:assigns]
  )
end
