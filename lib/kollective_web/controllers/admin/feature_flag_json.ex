defmodule KollectiveWeb.Admin.FeatureFlagJSON do
  @doc """
  Serializes a list collection of feature flags.
  """
  def index(%{feature_flags: feature_flags}) do
    %{data: Enum.map(feature_flags, &data/1)}
  end

  @doc """
  Serializes a single structural feature flag entity response.
  """
  def show(%{feature_flag: feature_flag}) do
    %{
      message: "System configuration matrix synchronized successfully.",
      data: data(feature_flag)
    }
  end

  def data(feature_flag) do
    %{
      key: feature_flag.key,
      enabled: feature_flag.enabled,
      description: feature_flag.description
    }
  end
end
