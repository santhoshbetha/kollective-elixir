defmodule Kollective.HTTPClient.Impl do
  @behaviour Kollective.HTTPClient

  @impl true
  def get(url, options) do
    Req.get(url, options)
  end
end
