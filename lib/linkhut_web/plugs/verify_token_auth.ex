defmodule LinkhutWeb.Plugs.VerifyTokenAuth do
  @moduledoc """
  Use this plug to authenticate a token contained in the header or as a request parameter.
  """
  use Plug.Builder

  alias ExOauth2Provider.Plug.{
    VerifyHeader,
    EnsureAuthenticated
    }

  import ExOauth2Provider.Plug, only: [current_resource_owner: 1]

  plug VerifyHeader, otp_app: :linkhut, realm: "Bearer"
  plug :verify_request_parameter
  plug EnsureAuthenticated, otp_app: :linkhut
  plug :set_current_user

  defp verify_request_parameter(conn, _) do
    conn
    |> fetch_token()
    |> verify_token(conn)
  end

  defp fetch_token(%Plug.Conn{query_params: %{"auth_token" => token}}) do
    token
  end

  defp fetch_token(_), do: nil

  defp verify_token(nil, conn), do: conn
  defp verify_token("", conn), do: conn

  defp verify_token(token, conn) do
    access_token = ExOauth2Provider.authenticate_token(token, otp_app: :linkhut)

    ExOauth2Provider.Plug.set_current_access_token(conn, access_token)
  end

  defp set_current_user(conn, _) do
    if user = current_resource_owner(conn) do
      assign(conn, :current_user, user)
    else
      halt(conn)
    end
  end
end
