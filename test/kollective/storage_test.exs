defmodule Kollective.StorageTest do
  use ExUnit.Case, async: true

  describe "cdn_domain/0" do
    test "defaults to the same-origin /media proxy, never the R2 S3 API endpoint" do
      domain = Kollective.Storage.cdn_domain()

      # The raw *.r2.cloudflarestorage.com URL requires S3 auth headers and is
      # NOT a public CDN. Browsers must be pointed at the /media proxy, which
      # streams objects from R2 server-side (see MediaProxyController).
      refute domain =~ "r2.cloudflarestorage.com"
      assert domain == "/media"
    end
  end
end
