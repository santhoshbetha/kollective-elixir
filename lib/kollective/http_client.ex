defmodule Kollective.HTTPClient do
  @callback get(String.t(), keyword()) :: {:ok, Req.Response.t()} | {:error, term()}
end
