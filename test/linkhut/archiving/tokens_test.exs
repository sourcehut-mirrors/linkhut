defmodule Linkhut.Archiving.TokensTest do
  use ExUnit.Case, async: true

  alias Linkhut.Archiving.Tokens

  describe "generate_token/1" do
    test "returns a non-empty string" do
      token = Tokens.generate_token(42)
      assert is_binary(token)
      assert token != ""
    end

    test "different snapshot IDs produce different tokens" do
      token1 = Tokens.generate_token(1)
      token2 = Tokens.generate_token(2)
      assert token1 != token2
    end
  end

  describe "verify_token/1" do
    test "successfully verifies a valid token" do
      token = Tokens.generate_token(42)
      assert {:ok, 42} = Tokens.verify_token(token)
    end

    test "returns error for tampered token" do
      assert {:error, :invalid_token} = Tokens.verify_token("invalid-token")
    end

    test "returns error for empty token" do
      assert {:error, :invalid_token} = Tokens.verify_token("")
    end
  end
end
