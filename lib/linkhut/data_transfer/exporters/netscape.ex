defmodule Linkhut.DataTransfer.Exporters.Netscape do
  @moduledoc """
  Exports bookmarks in the Netscape Bookmark File Format.
  """
  @behaviour Linkhut.DataTransfer.Exporter

  @impl true
  def format_name, do: "Netscape"

  @impl true
  def file_extension, do: "html"

  @impl true
  def content_type, do: "text/html"

  @impl true
  def render_header do
    """
    <!DOCTYPE NETSCAPE-Bookmark-file-1>
    <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
    <!-- This is an automatically generated file.
    It will be read and overwritten.
    Do Not Edit! -->
    <TITLE>Bookmarks</TITLE>
    <H1>Bookmarks</H1>
    <DL><p>
    """
  end

  @impl true
  def render_link(link) do
    url = Plug.HTML.html_escape_to_iodata(link.url)
    title = Plug.HTML.html_escape_to_iodata(link.title)
    tags = Plug.HTML.html_escape_to_iodata(Enum.join(link.tags, ","))
    notes = Plug.HTML.html_escape_to_iodata(link.notes)
    add_date = DateTime.to_unix(link.inserted_at, :second) |> Integer.to_string()

    [
      "<DT><A HREF=\"",
      url,
      "\" ADD_DATE=\"",
      add_date,
      "\" PRIVATE=\"",
      if(link.is_private, do: "1", else: "0"),
      "\" TAGS=\"",
      tags,
      "\">",
      title,
      "</A>\n<DD>",
      notes,
      "\n"
    ]
  end

  @impl true
  def render_footer do
    "</DL><p>"
  end
end
