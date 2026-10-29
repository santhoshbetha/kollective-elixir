defmodule KollectiveWeb.Plugs.RequirePersonalAccount do
  @moduledoc """
  Enforces that the current request is executed by a personal user profile.
  Blocks organization actors with 403 Forbidden.
  """
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, opts) do
    if is_organization_actor?(conn) do
      action = Phoenix.Controller.action_name(conn)

      message =
        case action do
          :join ->
            "Organizations cannot attend events. Please switch to your personal profile."

          :rsvp ->
            "Organizations cannot RSVP to events. Please switch to your personal profile."

          :create ->
            "Organizations cannot register businesses. Please switch to your personal profile."

          :create_proposal ->
            "Organizations cannot register businesses or submit proposals. Please switch to your personal profile."

          _ ->
            Keyword.get(
              opts,
              :message,
              "This action is restricted to personal accounts. Organizations are not permitted to perform this action."
            )
        end

      conn
      |> put_status(:forbidden)
      |> json(%{
        error: "forbidden",
        message: message
      })
      |> halt()
    else
      conn
    end
  end

  def is_organization_actor?(conn) do
    conn.assigns[:current_organization] != nil or
      conn.assigns[:account_type] == :organization or
      (conn.assigns[:current_org_id] != nil and conn.assigns[:current_org_id] != "")
  end
end
