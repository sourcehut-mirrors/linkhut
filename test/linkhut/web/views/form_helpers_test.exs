defmodule Linkhut.Web.FormHelpersTest do
  defmodule TestSchema do
    use Ecto.Schema

    schema "test_schema" do
      field :username, :string
      field :password, :string, virtual: true
    end
  end

  use ExUnit.Case

  alias Linkhut.Web.FormHelpers

  test "renders text input" do
    changeset =
      Ecto.Changeset.cast(
        %TestSchema{},
        %{username: "foo"},
        [:username]
      )

    form = Phoenix.HTML.FormData.to_form(changeset, [])

    html = Phoenix.HTML.safe_to_string(FormHelpers.input(form, :username))

    assert html == """
           <label for=\"test_schema_username\">Username</label>\
           <input id=\"test_schema_username\" name=\"test_schema[username]\" type=\"text\" value=\"foo\">\
           """
  end

  test "renders text input with errors" do
    {:error, changeset} =
      Ecto.Changeset.cast(
        %TestSchema{},
        %{username: "foo"},
        [:username]
      )
      |> Ecto.Changeset.validate_length(:username, min: 4)
      |> Ecto.Changeset.apply_action(:insert)

    form = Phoenix.HTML.FormData.to_form(changeset, [])

    html = Phoenix.HTML.safe_to_string(FormHelpers.input(form, :username))

    assert html == """
           <div class=\"invalid\">\
           <label for=\"test_schema_username\">Username</label>\
           <input id=\"test_schema_username\" name=\"test_schema[username]\" type=\"text\" value=\"foo\">\
           <ul>\
           <li class=\"invalid\">should be at least 4 character(s)</li>\
           </ul>\
           </div>\
           """
  end
end
