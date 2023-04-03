defmodule Linkhut.ConfigTest do
  use Linkhut.DataCase

  test "get/1 with an atom" do
    assert Linkhut.Config.get(Linkhut) == Application.get_env(:linkhut, Linkhut)
    assert Linkhut.Config.get(:qwertyuiop) == nil
    assert Linkhut.Config.get(:qwertyuiop, true) == true
  end

  test "get/1 with a list of keys" do
    assert Linkhut.Config.get([Linkhut, :ifttt]) ==
             Keyword.get(Application.get_env(:linkhut, Linkhut), :ifttt)

    assert Linkhut.Config.get([Linkhut.Web.Endpoint, :render_errors, :view]) ==
             get_in(
               Application.get_env(
                 :linkhut,
                 Linkhut.Web.Endpoint
               ),
               [:render_errors, :view]
             )

    assert Linkhut.Config.get([:qwerty, :uiop]) == nil
    assert Linkhut.Config.get([:qwerty, :uiop], true) == true
  end

  test "get!/1" do
    assert Linkhut.Config.get!(Linkhut) == Application.get_env(:linkhut, Linkhut)

    assert Linkhut.Config.get!([Linkhut, :ifttt]) ==
             Keyword.get(Application.get_env(:linkhut, Linkhut), :ifttt)

    assert_raise(Linkhut.Config.Error, fn ->
      Linkhut.Config.get!(:qwertyuiop)
    end)

    assert_raise(Linkhut.Config.Error, fn ->
      Linkhut.Config.get!([:qwerty, :uiop])
    end)
  end
end
