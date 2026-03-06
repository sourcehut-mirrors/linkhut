defmodule LinkhutWeb.ErrorJSONTest do
  use LinkhutWeb.ConnCase, async: true

  alias LinkhutWeb.Api.IFTTT.Errors.BadRequestError

  test "renders 400.json with BadRequestError" do
    conn = %Plug.Conn{assigns: %{reason: %BadRequestError{message: "missing parameters"}}}

    result = LinkhutWeb.ErrorJSON.render("400.json", %{conn: conn})

    assert %{errors: [%{status: "SKIP", message: "missing parameters"}]} = result
  end

  test "renders 400.json with generic error" do
    conn = %Plug.Conn{assigns: %{reason: %RuntimeError{message: "something else"}}}

    result = LinkhutWeb.ErrorJSON.render("400.json", %{conn: conn})

    assert %{errors: [%{message: "Bad Request"}]} = result
  end

  test "renders 500.json" do
    result = LinkhutWeb.ErrorJSON.render("500.json", %{})

    assert %{errors: [%{message: "Internal Server Error"}]} = result
  end

  test "renders 404.json" do
    result = LinkhutWeb.ErrorJSON.render("404.json", %{})

    assert %{errors: [%{message: "Not Found"}]} = result
  end
end
