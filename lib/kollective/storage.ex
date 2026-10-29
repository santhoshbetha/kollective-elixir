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
  Returns the active R2 key prefix.
  In :test and :e2e environments, defaults to "kollective-test".
  """
  def prefix do
    Application.get_env(:kollective, :r2_prefix) ||
      System.get_env("R2_PREFIX") ||
      System.get_env("R2_TEST_PREFIX") ||
      (if Mix.env() in [:test, :e2e], do: "kollective-test", else: nil)
  end

  @doc """
  Builds an object key with the environment prefix (if configured).
  Always standardizes on forward slashes for S3 / R2 keys.
  """
  def object_key(path) do
    case prefix() do
      nil -> String.trim_leading(path, "/")
      "" -> String.trim_leading(path, "/")
      p ->
        clean_prefix = String.trim(p, "/")
        clean_path = String.trim_leading(path, "/")
        "#{clean_prefix}/#{clean_path}"
    end
  end

  @doc """
  Returns the active R2 public domain or CDN base URL for serving uploaded assets.
  """
  def cdn_domain do
    Application.get_env(:kollective, :r2_public_domain) ||
      System.get_env("R2_PUBLIC_DOMAIN") ||
      "/media"
  end
end
