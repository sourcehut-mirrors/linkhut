defmodule LinkhutWeb.ErrorXMLTest do
  use LinkhutWeb.ConnCase, async: true

  test "renders 404.xml" do
    assert LinkhutWeb.ErrorXML.render("404.xml", %{}) == "Not Found"
  end

  test "renders 500.xml" do
    assert LinkhutWeb.ErrorXML.render("500.xml", %{}) == "Internal Server Error"
  end
end
