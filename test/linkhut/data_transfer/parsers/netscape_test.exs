defmodule Linkhut.DataTransfer.Parsers.NetscapeTest do
  use ExUnit.Case, async: true

  alias Linkhut.DataTransfer.Parsers.Netscape

  describe "parse_document/1" do
    test "parses a basic bookmark with all attributes" do
      html = """
      <DL><p>
      <DT><A HREF="https://example.com" ADD_DATE="1678900000" PRIVATE="1" TAGS="elixir,phoenix">Example</A>
      <DD>A description
      </DL>
      """

      assert {:ok, [{:ok, bookmark}]} = Netscape.parse_document(html)
      assert bookmark.url == "https://example.com"
      assert bookmark.title == "Example"
      assert bookmark.notes == "A description"
      assert bookmark.tags == "elixir,phoenix"
      assert bookmark.is_private == true
      assert %DateTime{} = bookmark.inserted_at
    end

    test "returns tags as raw string (splitting delegated to Ecto cast)" do
      html = """
      <DL><p>
      <DT><A HREF="https://example.com" TAGS="one,two,three">Tagged</A>
      </DL>
      """

      assert {:ok, [{:ok, bookmark}]} = Netscape.parse_document(html)
      assert bookmark.tags == "one,two,three"
    end

    test "missing tags defaults to empty string" do
      html = """
      <DL><p>
      <DT><A HREF="https://example.com">No Tags</A>
      </DL>
      """

      assert {:ok, [{:ok, bookmark}]} = Netscape.parse_document(html)
      assert bookmark.tags == ""
    end

    test "missing add_date does not crash" do
      html = """
      <DL><p>
      <DT><A HREF="https://example.com">No Date</A>
      </DL>
      """

      assert {:ok, [{:ok, bookmark}]} = Netscape.parse_document(html)
      assert %DateTime{} = bookmark.inserted_at
    end

    test "parses unix epoch timestamp" do
      html = """
      <DL><p>
      <DT><A HREF="https://example.com" ADD_DATE="1678900000">Epoch</A>
      </DL>
      """

      assert {:ok, [{:ok, bookmark}]} = Netscape.parse_document(html)
      assert bookmark.inserted_at == ~U[2023-03-15 17:06:40Z]
    end

    test "parses ISO 8601 timestamp" do
      html = """
      <DL><p>
      <DT><A HREF="https://example.com" ADD_DATE="2023-03-15T17:06:40Z">ISO</A>
      </DL>
      """

      assert {:ok, [{:ok, bookmark}]} = Netscape.parse_document(html)
      assert bookmark.inserted_at == ~U[2023-03-15 17:06:40Z]
    end

    test "parses JS Date.toString() timestamp" do
      html = """
      <DL><p>
      <DT><A HREF="https://example.com" ADD_DATE="Wed Mar 15 2023 17:06:40 GMT+0000 (Coordinated Universal Time)">JS Date</A>
      </DL>
      """

      assert {:ok, [{:ok, bookmark}]} = Netscape.parse_document(html)
      assert bookmark.inserted_at == ~U[2023-03-15 17:06:40Z]
    end

    test "parses JS Date.toString() with non-zero offset" do
      html = """
      <DL><p>
      <DT><A HREF="https://example.com" ADD_DATE="Thu Jan 01 2015 03:30:00 GMT+0530 (India Standard Time)">JS Date Offset</A>
      </DL>
      """

      assert {:ok, [{:ok, bookmark}]} = Netscape.parse_document(html)
      assert bookmark.inserted_at == ~U[2014-12-31 22:00:00Z]
    end

    test "parses JS Date.toString() with negative offset" do
      html = """
      <DL><p>
      <DT><A HREF="https://example.com" ADD_DATE="Thu Jan 01 2015 10:00:00 GMT-0500 (Eastern Standard Time)">JS Date Negative</A>
      </DL>
      """

      assert {:ok, [{:ok, bookmark}]} = Netscape.parse_document(html)
      assert bookmark.inserted_at == ~U[2015-01-01 15:00:00Z]
    end

    test "unrecognized date format falls back to current time" do
      html = """
      <DL><p>
      <DT><A HREF="https://example.com" ADD_DATE="not-a-date">Bad Date</A>
      </DL>
      """

      assert {:ok, [{:ok, bookmark}]} = Netscape.parse_document(html)
      assert %DateTime{} = bookmark.inserted_at
    end

    test "empty title defaults to URL" do
      html = """
      <DL><p>
      <DT><A HREF="https://example.com"></A>
      </DL>
      """

      assert {:ok, [{:ok, bookmark}]} = Netscape.parse_document(html)
      assert bookmark.title == "https://example.com"
    end

    test "nested title elements extracts text recursively" do
      html = """
      <DL><p>
      <DT><A HREF="https://example.com"><B>Bold</B> title</A>
      </DL>
      """

      assert {:ok, [{:ok, bookmark}]} = Netscape.parse_document(html)
      assert bookmark.title == "Bold title"
    end

    test "deeply nested title elements" do
      html = """
      <DL><p>
      <DT><A HREF="https://example.com"><span><em>Deep</em> text</span></A>
      </DL>
      """

      assert {:ok, [{:ok, bookmark}]} = Netscape.parse_document(html)
      assert bookmark.title == "Deep text"
    end

    test "DD with nested HTML content extracts text" do
      html = """
      <DL><p>
      <DT><A HREF="https://example.com">Title</A>
      <DD>Some <b>bold</b> and <i>italic</i> text
      </DL>
      """

      assert {:ok, [{:ok, bookmark}]} = Netscape.parse_document(html)
      assert bookmark.notes == "Some bold and italic text"
    end

    test "DD with complex nested HTML" do
      html = """
      <DL><p>
      <DT><A HREF="https://example.com">Title</A>
      <DD><p>A paragraph with <a href="http://link.com">a link</a></p>
      </DL>
      """

      assert {:ok, [{:ok, bookmark}]} = Netscape.parse_document(html)
      assert bookmark.notes =~ "A paragraph with"
      assert bookmark.notes =~ "a link"
    end

    test "private flag with value '1'" do
      html = """
      <DL><p>
      <DT><A HREF="https://example.com" PRIVATE="1">Private</A>
      </DL>
      """

      assert {:ok, [{:ok, bookmark}]} = Netscape.parse_document(html)
      assert bookmark.is_private == true
    end

    test "private flag with value 'true'" do
      html = """
      <DL><p>
      <DT><A HREF="https://example.com" PRIVATE="true">Private</A>
      </DL>
      """

      assert {:ok, [{:ok, bookmark}]} = Netscape.parse_document(html)
      assert bookmark.is_private == true
    end

    test "private flag with value 'yes'" do
      html = """
      <DL><p>
      <DT><A HREF="https://example.com" PRIVATE="yes">Private</A>
      </DL>
      """

      assert {:ok, [{:ok, bookmark}]} = Netscape.parse_document(html)
      assert bookmark.is_private == true
    end

    test "private flag with value '0' is not private" do
      html = """
      <DL><p>
      <DT><A HREF="https://example.com" PRIVATE="0">Public</A>
      </DL>
      """

      assert {:ok, [{:ok, bookmark}]} = Netscape.parse_document(html)
      assert bookmark.is_private == false
    end

    test "missing private flag defaults to false" do
      html = """
      <DL><p>
      <DT><A HREF="https://example.com">Public</A>
      </DL>
      """

      assert {:ok, [{:ok, bookmark}]} = Netscape.parse_document(html)
      assert bookmark.is_private == false
    end

    test "missing href returns error" do
      html = """
      <DL><p>
      <DT><A TAGS="test">No URL</A>
      </DL>
      """

      assert {:ok, [{:error, msg}]} = Netscape.parse_document(html)
      assert msg =~ "No URL found"
    end

    test "multiple bookmarks" do
      html = """
      <DL><p>
      <DT><A HREF="https://one.com">One</A>
      <DD>First
      <DT><A HREF="https://two.com">Two</A>
      <DD>Second
      <DT><A HREF="https://three.com">Three</A>
      </DL>
      """

      assert {:ok, bookmarks} = Netscape.parse_document(html)
      assert length(bookmarks) == 3

      assert [{:ok, b1}, {:ok, b2}, {:ok, b3}] = bookmarks
      assert b1.url == "https://one.com"
      assert b1.notes == "First"
      assert b2.url == "https://two.com"
      assert b2.notes == "Second"
      assert b3.url == "https://three.com"
      assert b3.notes == ""
    end

    test "folder-structured HTML" do
      html = """
      <!DOCTYPE NETSCAPE-Bookmark-file-1>
      <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
      <TITLE>Bookmarks</TITLE>
      <H1>Bookmarks</H1>
      <DL><p>
        <DT><H3>Folder</H3>
        <DL><p>
          <DT><A HREF="https://nested.com">Nested</A>
          <DD>Inside folder
        </DL><p>
      </DL><p>
      """

      assert {:ok, [{:ok, bookmark}]} = Netscape.parse_document(html)
      assert bookmark.url == "https://nested.com"
      assert bookmark.notes == "Inside folder"
    end

    test "non-link DT entries are silently skipped" do
      html = """
      <DL><p>
      <DT><A HREF="https://good.com">Good</A>
      <DT>Not a link at all
      </DL>
      """

      assert {:ok, bookmarks} = Netscape.parse_document(html)
      assert [{:ok, _good}] = bookmarks
    end

    test "empty file" do
      assert {:ok, []} = Netscape.parse_document("")
    end

    test "bookmark with empty DD" do
      html = """
      <DL><p>
      <DT><A HREF="https://example.com">Title</A>
      <DD>
      </DL>
      """

      assert {:ok, [{:ok, bookmark}]} = Netscape.parse_document(html)
      assert bookmark.notes == ""
    end
  end

  describe "can_parse?/1" do
    test "recognizes NETSCAPE-Bookmark-file-1 doctype" do
      html = """
      <!DOCTYPE NETSCAPE-Bookmark-file-1>
      <DL><p>
      <DT><A HREF="https://example.com">Test</A>
      </DL>
      """

      assert Netscape.can_parse?(html)
    end

    test "recognizes DT with A tag pattern" do
      html = """
      <DL><p>
      <DT><A HREF="https://example.com">Test</A>
      </DL>
      """

      assert Netscape.can_parse?(html)
    end

    test "rejects plain text" do
      refute Netscape.can_parse?("just some text")
    end

    test "rejects arbitrary HTML" do
      refute Netscape.can_parse?("<html><body><p>Hello</p></body></html>")
    end
  end
end
