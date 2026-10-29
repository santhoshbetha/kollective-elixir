defmodule KollectiveWeb.Plugs.BlockOrganizationActors do
  @moduledoc """
  Alias plug for RequirePersonalAccount.
  """
  alias KollectiveWeb.Plugs.RequirePersonalAccount

  def init(opts), do: RequirePersonalAccount.init(opts)
  def call(conn, opts), do: RequirePersonalAccount.call(conn, opts)
end
