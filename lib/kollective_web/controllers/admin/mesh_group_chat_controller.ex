defmodule KollectiveWeb.Admin.MeshGroupChatController do
  use KollectiveWeb, :controller
  require Logger

  alias Kollective.Repo
  alias Kollective.Chats.Conversation

  @doc """
  POST /api/v1/admin/chat_groups
  Creates a relational group thread entry inside PostgreSQL via Ecto,
  while propagating the live room metadata into the distributed Mnesia cluster layout.
  """
  def create(conn, params) do
    current_user = conn.assigns[:current_user] || conn.assigns[:user]
    group_params = Map.get(params, "group", params)
    title = Map.get(group_params, "title")
    description = Map.get(group_params, "description", "")

    # 1️⃣ ARRANGE THE RELATIONAL ECOSYSTEM CONTRACT:
    # We build a list of participants map blocks. Ecto's cast_assoc/3 will process
    # these entries to create row mappings inside your "participants" table automatically.
    # We seed the room with the creator user's account ID right away.
    creator_participant = %{"user_id" => current_user.id}

    # Process optional initial group invitees list if passed by your React configuration modal
    invited_participants =
      case Map.get(group_params, "invitee_ids", []) do
        list when is_list(list) -> Enum.map(list, fn uid -> %{"user_id" => uid} end)
        _ -> []
      end

    sql_attrs = %{
      "title" => title,
      "participants" => [creator_participant | invited_participants]
    }

    # 2️⃣ COMMIT TO LOCAL POSTGRES DISK PERSISTENCE STORAGE
    changeset = Conversation.changeset(%Conversation{}, sql_attrs)

    case Repo.insert(changeset) do
      {:ok, conversation} ->
        # 3️⃣ 🚀 INJECT IN-MEMORY CLUSTER-WIDE REPLICATION LAYER (MNESIA)
        # Mirrors the group room instance down to every node on the libcluster mesh instantly
        now_iso = DateTime.utc_now() |> DateTime.to_iso8601()

        mnesia_record = {
          :distributed_chat_groups,
          to_string(conversation.id),
          conversation.title,
          description,
          # Fits your application's tab categorization keys
          "cause",
          now_iso
        }

        case :mnesia.transaction(fn -> :mnesia.write(mnesia_record) end) do
          {:atomic, :ok} ->
            conn
            |> put_status(:created)
            |> json(%{
              status: "success",
              data: %{id: to_string(conversation.id), title: conversation.title}
            })

          {:aborted, reason} ->
            Logger.warning(
              "⚠️ [GROUP MESH EXCEPTION]: Mnesia write skipped, but SQL committed: #{inspect(reason)}"
            )

            conn
            |> put_status(:created)
            |> json(%{
              status: "success",
              data: %{id: to_string(conversation.id), title: conversation.title},
              warning:
                "Mesh memory propagation delayed. Room running over SQL persistence fallback mode."
            })
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        # Parse and output changeset verification parameters cleanly
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Enum.reduce(opts, msg, fn {k, v}, acc ->
              String.replace(acc, "%{#{k}}", to_string(v))
            end)
          end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to allocate relational group boundaries.", details: errors})
    end
  end
end
