defmodule LinkhutWeb.Settings.OauthHTML do
  use LinkhutWeb, :html

  import LinkhutWeb.Helpers
  import LinkhutWeb.SettingsComponents

  embed_templates "oauth_html/*"

  attr :personal_access_tokens, :list, required: true
  attr :preferences, :any, default: nil

  defp personal_token_list(assigns) do
    ~H"""
    <table :if={@personal_access_tokens != []}>
      <thead>
        <tr>
          <th>Token</th>
          <th>Comment</th>
          <th>Date issued</th>
          <th>Expires</th>
          <th class="btn-column"></th>
        </tr>
      </thead>
      <tbody>
        <tr :for={token <- @personal_access_tokens}>
          <td><code>{String.slice(token.token, 0, 8)}&hellip;</code></td>
          <td>{token.comment}</td>
          <td>{format_date(token.inserted_at, @preferences.timezone)}</td>
          <td>{format_date(NaiveDateTime.add(token.inserted_at, token.expires_in, :second), @preferences.timezone)}</td>
          <td><a class="button fill" href={~p"/_/oauth/personal-token/revoke/#{token.id}"}>Revoke</a></td>
        </tr>
      </tbody>
    </table>
    <p :if={@personal_access_tokens == []}>
      You have not created any personal access tokens.
    </p>
    """
  end

  attr :authorized_applications, :list, required: true
  attr :preferences, :any, default: nil

  defp authorized_application_list(assigns) do
    ~H"""
    <table :if={@authorized_applications != []}>
      <thead>
        <tr>
          <th>Name</th>
          <th>Owner</th>
          <th>First Authorized</th>
          <th>Expires</th>
          <th class="btn-column"></th>
        </tr>
      </thead>
      <tbody>
        <tr :for={application <- @authorized_applications}>
          <td>{application.name}</td>
          <td>{application.owner.username}</td>
          <td>{first_authorized_at(application, @preferences.timezone)}</td>
          <td>{expires_at(application, @preferences.timezone)}</td>
          <td>
            <.form for={%{}} action={~p"/_/oauth/revoke-access/#{application.uid}"} class="inline">
              <input type="hidden" name="uid" value={application.uid} />
              <.button type="submit">Revoke</.button>
            </.form>
          </td>
        </tr>
      </tbody>
    </table>
    <p :if={@authorized_applications == []}>
      You have not granted any third party clients access to your account.
    </p>
    """
  end

  attr :applications, :list, required: true

  defp application_list(assigns) do
    ~H"""
    <table :if={@applications != []}>
      <thead>
        <tr>
          <th>Name</th>
          <th>Application ID</th>
          <th>Active users</th>
          <th class="btn-column"></th>
        </tr>
      </thead>
      <tbody>
        <tr :for={application <- @applications}>
          <td>{application.name}</td>
          <td><code>{application.uid}</code></td>
          <td><code>{active_user_count(application)}</code></td>
          <td><a class="button fill" href={~p"/_/oauth/application/#{application.uid}/settings"}>Manage</a></td>
        </tr>
      </tbody>
    </table>
    <p :if={@applications == []}>
      You have not registered any OAuth applications yet.
    </p>
    """
  end

  defp active_user_count(application) do
    application.access_tokens
    |> Enum.uniq_by(& &1.resource_owner_id)
    |> Enum.count()
  end

  defp first_authorized_at(%{access_tokens: [token | _]}, tz),
    do: format_date(token.inserted_at, tz)

  defp first_authorized_at(_, _), do: ""

  defp expires_at(%{access_tokens: tokens}, tz) when tokens != [] do
    token = List.last(tokens)
    format_date(NaiveDateTime.add(token.inserted_at, token.expires_in, :second), tz)
  end

  defp expires_at(_, _), do: ""
end
