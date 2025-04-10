defmodule LinkhutWeb.SettingsComponents do
  @moduledoc """
  Provides UI components for Settings pages.
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

  attr :is_admin?, :boolean, required: true, doc: "should we show admin tabs"
  attr :request_path, :string, required: true, doc: "current path"

  def menu(assigns) do
    ~H"""
    <div class="navigation">
      <h2 class="navigation-header">Settings</h2>
      <ul class="navigation-tabs">
        <.nav_link
          :for={
            {to, name} <- [
              {~p"/_/profile", gettext("Profile")},
              {~p"/_/import", gettext("Import / Export")},
              {~p"/_/misc", gettext("Misc")},
              {~p"/_/oauth", gettext("OAuth")},
              @is_admin? && {~p"/_/admin", gettext("Admin")}
            ]
          }
          request_path={@request_path}
          to={to}
          name={name}
        />
      </ul>
    </div>
    <hr />
    """
  end

  defp starts_with_path?(request_path, to) do
    # Parse both paths to strip any query parameters
    %{path: request_path} = URI.parse(request_path)
    %{path: to_path} = URI.parse(to)

    String.starts_with?(request_path, String.trim_trailing(to_path, "/"))
  end
end
