defmodule LinkhutWeb.Api.IFTT.TestController do
  use LinkhutWeb, :controller

  alias Linkhut.Accounts
  alias Linkhut.Oauth

  plug :put_view, LinkhutWeb.Api.IFTT.TestView

  def setup(conn, _params) do
    ifttt_user = Accounts.get_user!(config(:user_id))
    ifttt_app = Oauth.get_application!(config(:application))

    access_token =
      Oauth.create_token!(ifttt_user, %{
        application: ifttt_app,
        scopes: "ifttt",
        expires_in: Timex.Duration.to_seconds(10, :minutes)
      })

    public_url = "https://example.com##{:crypto.strong_rand_bytes(3) |> Base.encode64()}"
    private_url = "https://example.com##{:crypto.strong_rand_bytes(3) |> Base.encode64()}"

    render(conn, "setup.json",
      token: access_token.token,
      public_url: public_url,
      private_url: private_url,
      date_time: DateTime.now!("Etc/UTC")
    )
  end

  defp config(key, default \\ nil) do
    Keyword.get(Application.get_env(:linkhut, :ifttt), key, default)
  end
end
