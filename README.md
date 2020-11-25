# linkhut

## Prerequisites

 * You need to have a PostgreSQL instance listening at localhost:5432 (you can change the hostname and the port in the `config/dev.exs` file).

## Dependencies

  * Install Elixir dependencies with `mix deps.get`
  * Install Node.js dependencies with `cd assets && npm install`

## Running

To start your linkhut server:
  * Create and migrate your database with `mix ecto.setup`
  * Start Phoenix endpoint with `mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.
