defmodule LinkhutWeb.LinkComponentsTest do
  use LinkhutWeb.ConnCase, async: true

  alias LinkhutWeb.LinkComponents
  alias Linkhut.Accounts.Preferences.UserPreference

  describe "show_url?/1" do
    test "returns true when no preferences (logged out)" do
      assert LinkComponents.show_url?(%{})
    end

    test "returns true when preference is true" do
      assert LinkComponents.show_url?(%{preferences: %UserPreference{show_url: true}})
    end

    test "returns false when preference is false" do
      refute LinkComponents.show_url?(%{preferences: %UserPreference{show_url: false}})
    end

    test "returns false when assign override is set" do
      refute LinkComponents.show_url?(%{
               show_url: false,
               preferences: %UserPreference{show_url: true}
             })
    end
  end

  describe "show_exact_dates?/1" do
    test "returns false when no preferences (logged out)" do
      refute LinkComponents.show_exact_dates?(%{})
    end

    test "returns false when preference is false" do
      refute LinkComponents.show_exact_dates?(%{
               preferences: %UserPreference{show_exact_dates: false}
             })
    end

    test "returns true when preference is true" do
      assert LinkComponents.show_exact_dates?(%{
               preferences: %UserPreference{show_exact_dates: true}
             })
    end

    test "returns true when assign override is set" do
      assert LinkComponents.show_exact_dates?(%{
               show_exact_dates: true,
               preferences: %UserPreference{show_exact_dates: false}
             })
    end
  end
end
