# lib/kollective_web/controllers/admin/staff_controller.ex
defmodule KollectiveWeb.Admin.StaffControllerX do
  use KollectiveWeb, :controller

  alias Kollective.Accounts.Accounts
  alias KollectiveWeb.ChangesetJSON

  @doc """
  POST /api/v1/admin/root/users/promote_moderator
  Promotes an active user account to the Moderator staff tier.
  """
  def promote_to_moderator(conn, %{"username" => username}) do
    admin = conn.assigns.current_user

    case Accounts.update_staff_role(username, :moderator, admin.id) do
      {:ok, user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message:
            "Account @#{user.username} successfully promoted to Moderator. Access desk keys generated."
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Targeted username does not exist on platform registers."})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(ChangesetJSON.error(%{changeset: changeset}))
    end
  end

  @doc """
  POST /api/v1/admin/root/users/promote_admin
  Promotes an active user account to the absolute Root Admin staff tier.
  """
  def promote_to_admin(conn, %{"username" => username}) do
    admin = conn.assigns.current_user

    case Accounts.update_staff_role(username, :admin, admin.id) do
      {:ok, user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message: "Account @#{user.username} successfully elevated to Root Administrator status."
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Targeted username does not exist on platform registers."})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(ChangesetJSON.error(%{changeset: changeset}))
    end
  end
end
