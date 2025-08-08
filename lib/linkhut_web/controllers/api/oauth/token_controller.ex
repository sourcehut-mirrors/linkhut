defmodule LinkhutWeb.Api.OAuth.TokenController do
  @moduledoc false
  use LinkhutWeb, :controller

  alias ExOauth2Provider.Token

  @spec create(Conn.t(), map()) :: Conn.t()
  def create(conn, params) do
    params
    |> Token.grant(otp_app: :linkhut)
    |> case do
      {:ok, access_token} ->
        json(conn, access_token)

      {:error, error, status} ->
        conn
        |> put_status(status)
        |> json(error)
    end
  end

  @spec revoke(Conn.t(), map()) :: Conn.t()
  def revoke(conn, params) do
    params
    |> Token.revoke(otp_app: :linkhut)
    |> case do
      {:ok, response} ->
        json(conn, response)

      {:error, error, status} ->
        conn
        |> put_status(status)
        |> json(error)
    end
  end
end
