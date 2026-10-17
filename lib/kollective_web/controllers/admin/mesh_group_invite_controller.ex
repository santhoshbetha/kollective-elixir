defmodule KollectiveWeb.Admin.MeshGroupInviteController do
  use KollectiveWeb, :controller
  require Logger

  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Chats.Participant
  alias Kollective.Accounts.User

  @doc """
  POST /api/v1/admin/chat_groups/:conversation_id/invite
  Adds a new user to an active group conversation across relational database lines [INDEX].
  """
  def create(conn, %{"conversation_id" => conv_id, "username" => invitee_username}) do
    clean_username = String.trim(invitee_username) |> String.downcase()

    # 1️⃣ RESOLVE THE TARGET USER PROFILE FIELD ATTRIBUTES
    # We locate the invitee by their unique username and extract their current public key string [INDEX]
    target_user =
      from(u in User, where: u.username == ^clean_username)
      |> Repo.one()

    case target_user do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Citizen account mapping profile not found on the network map."})

      user ->
        # 2️⃣ ARRANGE PARTICIPANT PARAMETERS CONTRACT [INDEX]
        # We pass the user's public key string directly onto the participant record row [INDEX]
        # for zero-latency lookups during browser-side media file encryption passes [INDEX].
        participant_attrs = %{
          "user_id" => user.id,
          "conversation_id" => conv_id,
          "public_key" => Map.get(user, :public_key)
        }

        changeset = Participant.changeset(%Participant{}, participant_attrs)

        case Repo.insert(changeset) do
          {:ok, _participant} ->
            # 3️⃣ 🚀 REAL-TIME CLUSTER EVENT BROADCAST
            # Alert the live Phoenix room lane so active frontend member lists update instantly
            KollectiveWeb.Endpoint.broadcast!(
              "chat_group:#{conv_id}",
              "member_joined",
              %{
                user_id: to_string(user.id),
                username: user.username,
                public_key: Map.get(user, :public_key),
                avatar: Map.get(user, :avatar, "/default-avatar.jpg")
              }
            )

            # Also push a notice down the invitee's private channel to pop up the room tab automatically
            KollectiveWeb.Endpoint.broadcast(
              "user_notifications:#{user.id}",
              "new_notification",
              %{
                "type" => "group_invite_alert",
                "conversation_id" => to_string(conv_id),
                "preview_text" => "You have been added to a secure distributed discussion hub."
              }
            )

            conn
            |> put_status(:created)
            |> json(%{
              status: "success",
              message: "User identity injected into group configuration ledger."
            })

          {:error, %Ecto.Changeset{} = changeset} ->
            # Catch duplicate insertion collisions elegantly using your unique constraint rule [INDEX]
            if changeset.errors[:user_id] &&
                 elem(changeset.errors[:user_id], 0) =~ "has already been taken" do
              conn
              |> put_status(:conflict)
              |> json(%{
                error: "Citizen signature is already a registered participant in this room space."
              })
            else
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "Database constraint failure mapping participant."})
            end
        end
    end
  end

  # GET /api/v1/chat_groups/:conversation_id/members
  def index(conn, %{"conversation_id" => conv_id}) do
    members =
      from(p in Participant,
        join: u in assoc(p, :user),
        where: p.conversation_id == ^conv_id,
        select: %{
          id: u.id,
          username: u.username,
          name: u.display_name,
          avatar: u.avatar_url,
          public_key: p.public_key
        }
      )
      |> Repo.all()
      |> Enum.map(fn member -> Map.update!(member, :id, &to_string/1) end)

    json(conn, %{data: members})
  end
end
