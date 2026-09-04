defmodule KollectiveWeb.CivicJSON do
  @moduledoc """
  JSON rendering view for Civic Controller operations.
  """
  alias KollectiveWeb.UserJSON

  def user(%{user: user}) do
    UserJSON.show(%{user: user})
  end
end
