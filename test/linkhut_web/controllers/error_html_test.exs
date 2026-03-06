defmodule LinkhutWeb.ErrorHTMLTest do
  use LinkhutWeb.ConnCase, async: true

  test "404 template is embedded" do
    # embed_templates generates internal functions dispatched by phoenix_template;
    # verify the template is reachable through the module's __phoenix_render__
    result = LinkhutWeb.ErrorHTML."404"(%{}) |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
    assert result =~ "<h1>404 Not Found</h1>"
    assert result =~ "Take me home"
  end

  test "render/2 fallback returns status message" do
    assert LinkhutWeb.ErrorHTML.render("500.html", %{}) == "Internal Server Error"
    assert LinkhutWeb.ErrorHTML.render("503.html", %{}) == "Service Unavailable"
  end
end
