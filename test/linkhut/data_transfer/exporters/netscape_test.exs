defmodule Linkhut.DataTransfer.Exporters.NetscapeTest do
  use ExUnit.Case, async: true

  alias Linkhut.DataTransfer.Exporters.Netscape

  describe "format metadata" do
    test "returns correct format name, extension, and content type" do
      assert Netscape.format_name() == "Netscape"
      assert Netscape.file_extension() == "html"
      assert Netscape.content_type() == "text/html"
    end
  end

  describe "render_header/0" do
    test "contains Netscape doctype" do
      header = Netscape.render_header()
      assert header =~ "<!DOCTYPE NETSCAPE-Bookmark-file-1>"
    end

    test "contains opening DL tag" do
      header = Netscape.render_header()
      assert header =~ "<DL><p>"
    end
  end

  describe "render_link/1" do
    test "renders a bookmark with all fields" do
      link = build_link()
      result = IO.iodata_to_binary(Netscape.render_link(link))

      assert result =~ ~s[HREF="https://example.com"]
      assert result =~ ~s[ADD_DATE="1678900000"]
      assert result =~ ~s[PRIVATE="0"]
      assert result =~ ~s[TAGS="elixir,phoenix"]
      assert result =~ ">Example</A>"
      assert result =~ "<DD>A great link"
    end

    test "renders private bookmark with PRIVATE=1" do
      link = build_link(is_private: true)
      result = IO.iodata_to_binary(Netscape.render_link(link))

      assert result =~ ~s[PRIVATE="1"]
    end

    test "renders public bookmark with PRIVATE=0" do
      link = build_link(is_private: false)
      result = IO.iodata_to_binary(Netscape.render_link(link))

      assert result =~ ~s[PRIVATE="0"]
    end

    test "HTML-escapes URL" do
      link = build_link(url: "https://example.com/search?q=a&b=c")
      result = IO.iodata_to_binary(Netscape.render_link(link))

      assert result =~ ~s[HREF="https://example.com/search?q=a&amp;b=c"]
    end

    test "HTML-escapes title" do
      link = build_link(title: "Tom & Jerry <3")
      result = IO.iodata_to_binary(Netscape.render_link(link))

      assert result =~ ">Tom &amp; Jerry &lt;3</A>"
    end

    test "HTML-escapes notes" do
      link = build_link(notes: "Use <script>alert('xss')</script>")
      result = IO.iodata_to_binary(Netscape.render_link(link))

      assert result =~ "<DD>Use &lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;"
    end

    test "handles empty tags" do
      link = build_link(tags: [])
      result = IO.iodata_to_binary(Netscape.render_link(link))

      assert result =~ ~s[TAGS=""]
    end

    test "handles empty notes" do
      link = build_link(notes: "")
      result = IO.iodata_to_binary(Netscape.render_link(link))

      assert result =~ "<DD>\n"
    end
  end

  describe "render_footer/0" do
    test "contains closing DL tag" do
      assert Netscape.render_footer() =~ "</DL><p>"
    end
  end

  describe "roundtrip" do
    test "exported bookmark can be parsed back" do
      alias Linkhut.DataTransfer.Parsers

      link = build_link()

      exported =
        IO.iodata_to_binary([
          Netscape.render_header(),
          Netscape.render_link(link),
          Netscape.render_footer()
        ])

      assert {:ok, [{:ok, parsed}]} = Parsers.Netscape.parse_document(exported)
      assert parsed.url == link.url
      assert parsed.title == link.title
      assert parsed.notes == link.notes
      assert parsed.tags == Enum.join(link.tags, ",")
      assert parsed.is_private == link.is_private
    end
  end

  defp build_link(overrides \\ []) do
    %{
      url: "https://example.com",
      title: "Example",
      notes: "A great link",
      tags: ["elixir", "phoenix"],
      is_private: false,
      inserted_at: DateTime.from_unix!(1_678_900_000)
    }
    |> Map.merge(Map.new(overrides))
  end
end
