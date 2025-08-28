defmodule Linkhut.Archiving.Tokens do
  @moduledoc "Manages short-lived tokens for snapshot access"

  @token_validity_minutes 15

  @doc """
  Generates a short-lived token for archive access.
  The token contains the snapshot ID.
  """
  def generate_token(snapshot_id) when is_integer(snapshot_id) do
    Phoenix.Token.sign(LinkhutWeb.Endpoint, "archive_token", snapshot_id)
  end

  @doc """
  Verifies and decodes an archive token.
  Returns {:ok, snapshot_id} if valid, {:error, :invalid_token} if expired/invalid.
  """
  def verify_token(token) do
    case Phoenix.Token.verify(LinkhutWeb.Endpoint, "archive_token", token,
           max_age: @token_validity_minutes * 60
         ) do
      {:ok, snapshot_id} -> {:ok, snapshot_id}
      {:error, _} -> {:error, :invalid_token}
    end
  end
end
