defmodule Linkhut.Accounts.PreferencesTest do
  use Linkhut.DataCase

  alias Linkhut.Accounts.Preferences
  alias Linkhut.Accounts.Preferences.UserPreference

  import Linkhut.AccountsFixtures

  describe "get_or_default/1" do
    test "returns default struct when no preferences exist" do
      user = user_fixture()

      pref = Preferences.get_or_default(user)

      assert %UserPreference{} = pref
      assert pref.user_id == user.id
      assert pref.show_url == true
      assert pref.show_exact_dates == false
      assert pref.default_private == false
      assert pref.strip_tracking_params == false
      assert pref.timezone == nil
    end

    test "returns saved preferences when they exist" do
      user = user_fixture()
      {:ok, _} = Preferences.upsert(user, %{show_url: false, timezone: "America/New_York"})

      pref = Preferences.get_or_default(user)

      assert pref.show_url == false
      assert pref.timezone == "America/New_York"
    end
  end

  describe "upsert/2" do
    test "creates preferences for user without existing preferences" do
      user = user_fixture()

      assert {:ok, pref} = Preferences.upsert(user, %{show_exact_dates: true})
      assert pref.user_id == user.id
      assert pref.show_exact_dates == true
      assert pref.show_url == true
    end

    test "updates existing preferences" do
      user = user_fixture()
      {:ok, _} = Preferences.upsert(user, %{show_url: false})
      {:ok, pref} = Preferences.upsert(user, %{show_url: true, default_private: true})

      assert pref.show_url == true
      assert pref.default_private == true
    end

    test "toggles strip_tracking_params" do
      user = user_fixture()
      {:ok, pref} = Preferences.upsert(user, %{strip_tracking_params: true})
      assert pref.strip_tracking_params == true

      {:ok, pref} = Preferences.upsert(user, %{strip_tracking_params: false})
      assert pref.strip_tracking_params == false
    end

    test "validates timezone" do
      user = user_fixture()

      assert {:error, changeset} = Preferences.upsert(user, %{timezone: "Invalid/Zone"})
      assert "is not a valid timezone" in errors_on(changeset).timezone
    end

    test "accepts valid timezone" do
      user = user_fixture()

      assert {:ok, pref} = Preferences.upsert(user, %{timezone: "Europe/London"})
      assert pref.timezone == "Europe/London"
    end

    test "clears timezone when set to empty string" do
      user = user_fixture()
      {:ok, _} = Preferences.upsert(user, %{timezone: "Europe/London"})
      {:ok, pref} = Preferences.upsert(user, %{timezone: ""})

      assert pref.timezone == nil
    end
  end

  describe "change/2" do
    test "returns a changeset" do
      pref = %UserPreference{}
      assert %Ecto.Changeset{} = Preferences.change(pref)
    end

    test "returns a changeset with changes" do
      pref = %UserPreference{}
      changeset = Preferences.change(pref, %{show_url: false})
      assert changeset.changes == %{show_url: false}
    end
  end
end
