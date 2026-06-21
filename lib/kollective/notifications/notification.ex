defmodule Kollective.Notifications.Notification do
  use Kollective.Schemas.Schema

  @type t :: %__MODULE__{}

  @notification_types ~w{
    favourite
    follow
    mention
    reply
    reblog
    poll_expired
    chat_mention
    emoji_reaction
    report
    participation_accepted
    participation_request
    event_reminder
    event_update
    voice_alert
  }

  schema "notifications" do
    # This is an enum type in the database. If you add a new notification type,
    # remember to add a migration to add it to the `notification_type` enum
    # as well.
    #(The Verb)
    #This describes what happened. It is used to decide the text and icon in the UI.
    field :type, :string                # "mention", "favourite", "follow", "voice_alert"
    field :read, :boolean, default: false

    # To store which event was cancelled (so the user can see it in their notification history later),
    # I highly recommend adding a metadata JSONB field to your notifications table.
    # Usage: Now you can store: metadata: %{event_title: "Protest at City Hall", event_id: "..."}
    field :metadata, :map, default: %{}

    # The person seeing the notification
    belongs_to :user, Kollective.Accounts.User, foreign_key: :user_id, type: Kollective.Schemas.ULIDType
    # The person who did the action
    belongs_to :actor, Kollective.Accounts.User, foreign_key: :actor_id, type: Kollective.Schemas.ULIDType

    # Optional: Explicit link to the post
    belongs_to :post, Kollective.Posts.Post, type: Kollective.Schemas.ULIDType
    # Optional: Explicit link to the event
    belongs_to :event, Kollective.Events.Event, type: Kollective.Schemas.ULIDType

    field :target_id            # The ID of the Post, Comment, or User
    # (The Noun)
    # This describes what object the action happened to. It is essential for Ecto.ULID polymorphic preloading,
    # where a target_id could refer to multiple different tables.
    field :target_type, :string # "Post", "User", "Comment", "Chat"

    field :urgency, Ecto.Enum, values: [:low, :medium, :high], default: :medium

    timestamps()
  end

  def changeset(notification, attrs) do
    notification
    |> Ecto.Changeset.cast(attrs, [:type, :read, :metadata, :user_id, :actor_id, :post_id, :event_id, :target_id, :target_type])
    |> validate_required([:type, :user_id, :actor_id])
    |> validate_inclusion(:type, @notification_types)
    |> Ecto.Changeset.foreign_key_constraint(:user_id)
    |> Ecto.Changeset.foreign_key_constraint(:actor_id)
    |> Ecto.Changeset.foreign_key_constraint(:post_id)
    |> Ecto.Changeset.foreign_key_constraint(:event_id)
    |> Ecto.Changeset.foreign_key_constraint(:target_id)
  end
end

#create index(:notifications, [:user_id])
# Index this for fast grouping lookups
#create index(:notifications, [:user_id, :target_id, :type])
#create index(:notifications, [:user_id, :read_at]) # Fast lookup for unread counts
