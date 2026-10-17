defmodule KollectiveWeb.AdminUserJSON do
  @moduledoc """
  JSON serializer for AdminUserController.
  """

  def index(%{users: users}) do
    %{data: for(user <- users, do: data(user))}
  end

  def show(%{user: user}) do
    %{data: data(user)}
  end

  def data(user) do
    KollectiveWeb.UserJSON.data(user)
  end
end
