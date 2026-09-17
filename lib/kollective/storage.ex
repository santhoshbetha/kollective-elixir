defmodule Kollective.Storage do
  @moduledoc """
  Central helper module for managing Cloudflare R2 / S3 Object Storage configuration and endpoint resolution.
  """

  @doc """
  Returns the active R2/S3 bucket name.
  Defaults to "kollective".
  """
  def bucket_name do
    Application.get_env(:kollective, :r2_bucket) ||
      System.get_env("R2_BUCKET_NAME") ||
      Application.get_env(:waffle, :bucket) ||
      "kollective"
  end

  @doc """
  Returns the active R2 public domain or CDN base URL for serving uploaded assets.
  """
  def cdn_domain do
    Application.get_env(:kollective, :r2_public_domain) ||
      System.get_env("R2_PUBLIC_DOMAIN") ||
      "https://47701ef2e87f29505064cb21fd2513ed.r2.cloudflarestorage.com/kollective"
  end
end
