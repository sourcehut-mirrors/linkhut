# SingleFile

An elixir wrapper for installing and invoking [single-file-cli](https://github.com/gildas-lormeau/single-file-cli).

## Installation

```elixir
def deps do
  [
    {:single_file, "~> 0.1.0"}
  ]
end
```

Once installed, change your `config/config.exs` to pick your version of choice:

```elixir
config :single_file, version: "2.0.75"
```
Now you can install single-file-cli by running:

```shell
$ mix single_file.install
```

