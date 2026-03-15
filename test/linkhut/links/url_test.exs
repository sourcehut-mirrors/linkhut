defmodule Linkhut.Links.UrlTest do
  use ExUnit.Case, async: true

  alias Linkhut.Links.Url

  describe "strip_tracking_params/1" do
    test "strips UTM params and preserves non-tracking params" do
      url = "https://example.com/page?utm_source=twitter&utm_medium=social&ref=homepage"
      assert Url.strip_tracking_params(url) == "https://example.com/page?ref=homepage"
    end

    test "strips mixed tracking and non-tracking params" do
      url = "https://example.com/?q=elixir&fbclid=abc123&page=2&gclid=xyz"
      assert Url.strip_tracking_params(url) == "https://example.com/?q=elixir&page=2"
    end

    test "removes query string entirely when all params are tracking" do
      url = "https://example.com/article?utm_source=newsletter&utm_campaign=spring&fbclid=abc"
      assert Url.strip_tracking_params(url) == "https://example.com/article"
    end

    test "returns URL unchanged when no query string" do
      url = "https://example.com/page"
      assert Url.strip_tracking_params(url) == url
    end

    test "returns URL unchanged with empty query string" do
      url = "https://example.com/page?"
      assert Url.strip_tracking_params(url) == url
    end

    test "returns URL unchanged when no tracking params present" do
      url = "https://example.com/search?q=elixir&page=1"
      assert Url.strip_tracking_params(url) == url
    end

    test "preserves fragment after stripping" do
      url = "https://example.com/page?utm_source=twitter&ref=top#section-2"
      assert Url.strip_tracking_params(url) == "https://example.com/page?ref=top#section-2"
    end

    test "matches params case-sensitively" do
      url = "https://example.com/?UTM_SOURCE=twitter&UTM_MEDIUM=social&keep=yes"
      assert Url.strip_tracking_params(url) == url
    end

    test "idempotency: stripping twice gives same result" do
      url = "https://example.com/page?utm_source=twitter&ref=homepage&fbclid=abc"
      once = Url.strip_tracking_params(url)
      twice = Url.strip_tracking_params(once)
      assert once == twice
    end

    test "strips Google Ads params" do
      url = "https://example.com/?gclid=abc&gclsrc=aw.ds&_ga=123&other=keep"
      assert Url.strip_tracking_params(url) == "https://example.com/?other=keep"
    end

    test "strips HubSpot params" do
      url = "https://example.com/?_hsenc=abc&_hsmi=123&__hstc=456&keep=yes"
      assert Url.strip_tracking_params(url) == "https://example.com/?keep=yes"
    end

    test "preserves fragment when all query params removed" do
      url = "https://example.com/page?utm_source=x#anchor"
      assert Url.strip_tracking_params(url) == "https://example.com/page#anchor"
    end

    test "does not re-encode slashes in non-tracking param values" do
      url = "https://example.com/login?next=/some/path/&fbclid=abc123"
      assert Url.strip_tracking_params(url) == "https://example.com/login?next=/some/path/"
    end

    test "does not convert plus to percent-encoding in non-tracking param values" do
      url = "https://example.com/search?keywords=hello+world&utm_source=twitter"
      assert Url.strip_tracking_params(url) == "https://example.com/search?keywords=hello+world"
    end

    test "preserves value-less query params without appending =" do
      url = "https://example.com/video?t&utm_source=twitter"
      assert Url.strip_tracking_params(url) == "https://example.com/video?t"
    end

    test "strips tracking param with empty value" do
      url = "https://example.com/page?utm_source=&keep=yes"
      assert Url.strip_tracking_params(url) == "https://example.com/page?keep=yes"
    end

    test "returns URL unchanged when query marker is followed by fragment" do
      url = "https://example.com/?#anchor"
      assert Url.strip_tracking_params(url) == url
    end
  end

  describe "tracking_params/0" do
    test "returns a MapSet" do
      assert %MapSet{} = Url.tracking_params()
    end

    test "contains well-known tracking params" do
      params = Url.tracking_params()
      assert "utm_source" in params
      assert "fbclid" in params
      assert "gclid" in params
      assert "msclkid" in params
    end
  end

  describe "tracking_params_by_source/0" do
    test "returns a list of {source, params} tuples" do
      sources = Url.tracking_params_by_source()
      assert is_list(sources)

      for {source, params} <- sources do
        assert is_binary(source)
        assert is_list(params)
        assert Enum.all?(params, &is_binary/1)
      end
    end

    test "every param in by_source is in the tracking_params set" do
      all_params = Url.tracking_params()

      for {_source, params} <- Url.tracking_params_by_source(),
          param <- params do
        assert param in all_params,
               "#{param} is in tracking_params_by_source but not in tracking_params"
      end
    end
  end

  describe "normalize_host/1" do
    test "lowercases host for HTTP URLs" do
      assert Url.normalize_host("http://EXAMPLE.COM/Path") == "http://example.com/Path"
    end

    test "lowercases host for HTTPS URLs" do
      assert Url.normalize_host("https://Example.COM/Path") == "https://example.com/Path"
    end

    test "lowercases scheme" do
      assert Url.normalize_host("HTTP://example.com") == "http://example.com"
      assert Url.normalize_host("HTTPS://example.com") == "https://example.com"
    end

    test "strips default ports" do
      assert Url.normalize_host("http://example.com:80/path") == "http://example.com/path"
      assert Url.normalize_host("https://example.com:443/path") == "https://example.com/path"
    end

    test "preserves non-default ports" do
      assert Url.normalize_host("http://example.com:8080/path") ==
               "http://example.com:8080/path"
    end

    test "preserves path, query, and fragment" do
      assert Url.normalize_host("https://Example.COM/Path?q=1&b=2#frag") ==
               "https://example.com/Path?q=1&b=2#frag"
    end

    test "is idempotent" do
      url = "https://example.com/path?q=1"
      assert Url.normalize_host(url) == url
      assert Url.normalize_host(Url.normalize_host(url)) == url
    end

    test "returns unchanged for URLs without a host" do
      assert Url.normalize_host("file:///some/path") == "file:///some/path"
    end

    test "returns unchanged for malformed input" do
      assert Url.normalize_host("not a url") == "not a url"
    end

    test "normalizes other DNS-based schemes" do
      assert Url.normalize_host("ftp://FTP.Example.COM/pub") == "ftp://ftp.example.com/pub"
      assert Url.normalize_host("gemini://EXAMPLE.COM/page") == "gemini://example.com/page"
      assert Url.normalize_host("gopher://EXAMPLE.COM/1") == "gopher://example.com/1"
    end

    test "does not lowercase host for unknown schemes" do
      assert Url.normalize_host("ipfs://QmAbCdEf/path") == "ipfs://QmAbCdEf/path"
    end
  end

  describe "normalize/1" do
    test "normalizes host and strips tracking params" do
      assert Url.normalize("https://Example.COM/page?utm_source=twitter&ref=top") ==
               "https://example.com/page?ref=top"
    end

    test "is idempotent" do
      url = "https://Example.COM/page?utm_source=twitter&ref=top"
      once = Url.normalize(url)
      twice = Url.normalize(once)
      assert once == twice
    end

    test "returns unchanged when nothing to normalize" do
      url = "https://example.com/path?q=1"
      assert Url.normalize(url) == url
    end
  end
end
