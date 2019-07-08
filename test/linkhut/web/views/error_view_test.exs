defmodule Linkhut.Web.ErrorViewTest do
  use Linkhut.Web.ConnCase, async: true

  # Bring render_to_string/3 for testing custom views
  import Phoenix.View, only: [render_to_string: 3]

  test "renders 404.html" do
    assert render_to_string(Linkhut.Web.ErrorView, "404.html", []) =~ "Not Found"
  end

  test "renders 500.html" do
    assert render_to_string(Linkhut.Web.ErrorView, "500.html", []) == "Internal Server Error"
  end
end
