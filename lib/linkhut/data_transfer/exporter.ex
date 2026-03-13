defmodule Linkhut.DataTransfer.Exporter do
  @moduledoc """
  Behaviour for bookmark file format exporters.
  """

  @callback format_name() :: String.t()
  @callback file_extension() :: String.t()
  @callback content_type() :: String.t()
  @callback render_header() :: iodata()
  @callback render_link(Linkhut.Links.Link.t()) :: iodata()
  @callback render_footer() :: iodata()
end
