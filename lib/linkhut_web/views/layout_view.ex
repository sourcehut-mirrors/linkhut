defmodule LinkhutWeb.LayoutView do
  use LinkhutWeb, :view
  @ex_doc_version Mix.Project.config()[:version]

  @doc """
  Returns the linkhut version.
  """
  @spec version :: String.t()
  def version, do: @ex_doc_version
end
