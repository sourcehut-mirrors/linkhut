defmodule LinkhutWeb.NavigationComponents do
  @moduledoc """
  Shared navigation components (tab bars, nav links).
  """
  use LinkhutWeb, :html

  attr :request_path, :string, required: true, doc: "current path"
  attr :name, :string, required: true, doc: "the name of the navigation link"
  attr :to, :any, required: true, doc: "the destination of the navigation link"
  attr :is_active?, :boolean, doc: "whether the navigation link is active"

  def nav_link(%{request_path: request_path} = assigns) when not is_nil(request_path) do
    assigns
    |> assign(request_path: nil)
    |> assign_new(:is_active?, fn -> starts_with_path?(request_path, assigns.to) end)
    |> nav_link()
  end

  def nav_link(assigns) do
    ~H"""
    <li class={@is_active? && "active"}>
      <span :if={@is_active?}>{@name}</span>
      <a :if={!@is_active?} href={@to}>{@name}</a>
    </li>
    """
  end

  @doc false
  def starts_with_path?(request_path, to) do
    # Parse both paths to strip any query parameters
    %{path: request_path} = URI.parse(request_path)
    %{path: to_path} = URI.parse(to)
    to_path = String.trim_trailing(to_path, "/")

    String.starts_with?(request_path, to_path) and
      (String.length(request_path) == String.length(to_path) or
         String.at(request_path, String.length(to_path)) == "/")
  end
end
