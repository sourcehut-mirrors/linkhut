defmodule LinkhutWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use LinkhutWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  import Linkhut.Factory

  using do
    quote do
      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      alias LinkhutWeb.Router.Helpers, as: Routes

      import Linkhut.Factory

      # The default endpoint for testing
      @endpoint LinkhutWeb.Endpoint

      use LinkhutWeb, :verified_routes
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Linkhut.Repo)

    if !tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Linkhut.Repo, {:shared, self()})
    end

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Setup helper that registers and logs in users.

      setup :register_and_log_in_user

  It stores an updated connection and a registered user in the
  test context.
  """
  def register_and_log_in_user(%{conn: conn} = context) do
    user = Linkhut.AccountsFixtures.user_fixture()

    opts =
      context
      |> Map.take([:token_inserted_at])
      |> Enum.into([])

    %{conn: log_in_user(conn, user, opts), user: user}
  end

  @doc """
  Setup helper that registers, activates, and logs in a paying user.

      setup :register_and_log_in_paying_user
  """
  def register_and_log_in_paying_user(%{conn: conn} = context) do
    user =
      Linkhut.AccountsFixtures.user_fixture()
      |> Linkhut.AccountsFixtures.activate_user(:active_paying)

    opts =
      context
      |> Map.take([:token_inserted_at])
      |> Enum.into([])

    %{conn: log_in_user(conn, user, opts), user: user}
  end

  @doc """
  Logs the given `user` into the `conn`.

  It returns an updated `conn`.
  """
  def log_in_user(conn, user, opts \\ []) do
    token = Linkhut.Accounts.generate_user_session_token(user)

    maybe_set_token_inserted_at(token, opts[:token_inserted_at])

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  defp maybe_set_token_inserted_at(_token, nil), do: nil

  defp maybe_set_token_inserted_at(token, inserted_at) do
    Linkhut.AccountsFixtures.override_token_inserted_at(token, inserted_at)
  end

  @doc """
  Setup helper that registers and sets up a bearer token

      setup :register_and_set_up_api_token

  It stores an updated connection and a bearer token in the
  test context.
  """
  def register_and_set_up_api_token(%{conn: conn} = context) do
    user = Linkhut.AccountsFixtures.user_fixture()

    token =
      insert(:access_token,
        resource_owner_id: user.id,
        scopes: Map.get(context, :scopes, "posts:read tags:read")
      )

    conn =
      conn
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token.token}")
      |> Plug.Conn.put_req_header("accept", Map.get(context, :accept, "application/json"))

    %{conn: conn, user: user}
  end
end
