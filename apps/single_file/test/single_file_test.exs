defmodule SingleFileTest do
  use ExUnit.Case, async: true

  @version SingleFile.latest_version()

  test "run on default" do
    {output, code} = SingleFile.run(:default, ["--version"])
    assert code == 0
    assert output =~ @version
  end

  test "run on profile" do
    {output, code} = SingleFile.run(:another, ["--version"])
    assert code == 0
    assert output =~ @version
  end

  test "updates on install" do
    Application.put_env(:single_file, :version, "2.0.73")

    Mix.Task.rerun("single_file.install", ["--if-missing"])

    {output, code} = SingleFile.run(:default, ["--version"])
    assert code == 0
    assert output =~ "2.0.73"

    Application.delete_env(:single_file, :version)

    Mix.Task.rerun("single_file.install", ["--if-missing"])

    {output, code} = SingleFile.run(:default, ["--version"])
    assert code == 0
    assert output =~ @version
  end

  test "errors on invalid profile" do
    assert_raise ArgumentError,
                 ~r<unknown single_file profile. Make sure the profile named :foobar is defined>,
                 fn ->
                   assert SingleFile.run(:foobar, ["--version"])
                 end
  end
end
