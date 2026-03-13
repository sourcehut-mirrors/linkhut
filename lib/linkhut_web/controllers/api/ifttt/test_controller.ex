defmodule LinkhutWeb.Api.IFTTT.TestController do
  use LinkhutWeb, :controller

  alias Linkhut.Accounts
  alias Linkhut.Oauth

  plug :put_view, json: LinkhutWeb.Api.IFTTT.TestJSON

  def setup(conn, _params) do
    ifttt_user = Accounts.get_user!(Linkhut.Config.ifttt(:user_id))
    ifttt_app = Oauth.get_application!(Linkhut.Config.ifttt(:application))

    access_token =
      Oauth.create_token!(ifttt_user, %{
        application: ifttt_app,
        scopes: "ifttt",
        expires_in: 600
      })

    public_url = "https://example.com##{:crypto.strong_rand_bytes(3) |> Base.encode64()}"
    private_url = "https://example.com##{:crypto.strong_rand_bytes(3) |> Base.encode64()}"

    render(conn, :setup,
      token: access_token.token,
      public_url: public_url,
      private_url: private_url,
      date_time: DateTime.now!("Etc/UTC")
    )
  end
end
