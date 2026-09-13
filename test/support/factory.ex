# test/support/factory.ex
defmodule Kollective.Factory do
  use ExMachina.Ecto, repo: Kollective.Repo

  @doc """
  Generates a completely unique, valid ULID string wrapper.
  """
  def ulid_sequence do
    Ecto.ULID.generate()
  end

  # --- FACTORIES ---

  # test/support/factory.ex
  def user_factory do
    %Kollective.Accounts.User{
      id: ulid_sequence(),
      username: sequence(:username, &"user_#{&1}"),

      # Keep your true database columns:
      email: sequence(:email, &"user-#{&1}@kollective.com"),
      is_active: true,
      is_verified: false,
      is_admin: false,
      is_moderator: false,
      identity_hash: "mock_user_identity_hash_signature",
      experience_mode: "social_only"
    }
  end

  def post_factory do
    %Kollective.Posts.Post{
      id: Ecto.ULID.generate(),
      content: "Default post body content #kollective",

      # ⚡ FIXED: Aligns with belongs_to(:author, User, foreign_key: :user_id)
      author: build(:user)
    }
  end

  # test/support/factory.ex
  def post_attachment_factory do
    %Kollective.Posts.PostAttachment{
      id: Ecto.ULID.generate(),
      url: "https://r2.dev",
      media_type: "image/jpeg",
      blurhash: "L6PZfsi_00Kj%~j[fQj[",
      description: "Default factory image alt text caption metadata",

      # ⚡ FIXED: Instruct ExMachina to instantiate a real user struct node first
      # This guarantees the target ID satisfies the database foreign key check
      user: build(:user)
    }
  end

  # test/support/factory.ex
  def event_factory do
    %Kollective.Events.Event{
      id: ulid_sequence(),
      title: "Official Tech Summit",
      description: "Core objective description text goes here.",
      category: "standard",
      participation_format: "in_person",
      join_mode: "free",
      event_status: "published",
      target_scope: :local,
      origin_country: "US",
      show_banner: true,
      comments_count: 0,
      participants_count: 0,
      participation_request_count: 0,

      # ⚡ ADD THIS RELATIONSHIP (Maps to your schema's belongs_to :user)
      # ExMachina will build a fresh user model with its own valid ULID
      user: build(:user),

      # ⚡ Attach a pre-built factory city to keep relationship testing green
      origin_city: build(:city),

      # This satisfies your optional context layout relationship
      organization: build(:user)
    }
  end

  # test/support/factory.ex

  def participant_factory do
    %Kollective.Events.Participant{
      # Generate an automatic tracking ULID primary key
      id: ulid_sequence(),
      status: "attending",

      # Setup default parent relationships seamlessly
      event: build(:event),
      user: build(:user)
    }
  end

  def city_factory do
    %Kollective.Locations.City{
      # Generate an automatic tracking ULID primary key
      id: Ecto.ULID.generate(),
      name: sequence(:city_name, &"City #{&1}"),
      state: "CA",
      country: "US",
      latitude: 34.0522,
      longitude: -118.2437,

      # ⚡ FIXED: Add a unique, non-null sequence matching your schema's validation metrics
      external_id: sequence(:external_id, &"geoapify_place_node_id_#{&1}")
    }
  end

  # test/support/factory.ex
  def poll_factory do
    %Kollective.Polls.Poll{
      id: Ecto.ULID.generate(),
      multiple: false,
      non_anonymous: false,
      votes_count: 0,
      expired: false,
      # Set default expiration to 1 day into the future to satisfy custom validations
      expires_at:
        DateTime.utc_now() |> DateTime.add(86400, :second) |> DateTime.truncate(:second),
      post: build(:post)
    }
  end

  # test/support/factory.ex
  def post_reaction_factory do
    %Kollective.Posts.PostReaction{
      id: Ecto.ULID.generate(),
      emoji: "🔥",

      # Establish parent references safely to prevent structural constraint failures
      user: build(:user),
      post: build(:post)
    }
  end

  # test/support/factory.ex
  def user_relationship_factory do
    # Maps directly to the has_many relationships declared inside your User schema snippets
    %Kollective.Accounts.UserRelationship{
      id: Ecto.ULID.generate(),
      type: "follow",

      # Use arbitrary unique values for defaults
      source_id: Ecto.ULID.generate(),
      target_id: Ecto.ULID.generate()
    }
  end

  def buffered_notification_factory do
    %Kollective.Notifications.BufferedNotification{
      id: Ecto.ULID.generate(),
      type: "emoji_reaction",
      target_id: Ecto.ULID.generate(),

      # Generates a parent user schema link cleanly
      user_id: Ecto.ULID.generate()
    }
  end

  def business_factory do
    %Kollective.Businesses.Business{
      id: Ecto.ULID.generate(),
      name: sequence(:business_name, &"Business #{&1}"),
      description: "A valid local storefront business.",
      type: "existing",
      category: "food_beverage",
      sub_category: "restaurant",
      address: "123 Main St",
      city: "Los Angeles",
      state: "CA",
      zip: "90001",
      country: "US",
      email: sequence(:business_email, &"info-#{&1}@mybusiness.com"),
      phone: "213-555-0199",
      website: "https://mybusiness.com",
      legal_structure: "LLC",
      verification_status: "verified",
      user: build(:user),
      city_relation: build(:city),
      location: %Geo.Point{coordinates: {-118.2437, 34.0522}, srid: 4326}
    }
  end

  def business_proposal_factory do
    %Kollective.Businesses.Business{
      id: Ecto.ULID.generate(),
      name: sequence(:proposal_name, &"Proposal #{&1}"),
      description: "A grassroots community business proposal.",
      type: "proposals",
      category: "technology",
      sub_category: "software_saas",
      address: "456 Side St",
      city: "Los Angeles",
      state: "CA",
      zip: "90002",
      country: "US",
      email: sequence(:proposal_email, &"proposal-#{&1}@community.org"),
      phone: "213-555-0200",
      legal_structure: "Sole Proprietorship",
      verification_status: "unverified",
      user: build(:user),
      city_relation: build(:city),
      location: %Geo.Point{coordinates: {-118.2437, 34.0522}, srid: 4326}
    }
  end

  def comment_factory do
    %Kollective.Events.Comment{
      id: Ecto.ULID.generate(),
      content: "This is a great comment!",
      moderation_status: "approved",
      user: build(:user),
      event: build(:event)
    }
  end

  def comment_like_factory do
    %Kollective.Events.CommentLike{
      id: Ecto.ULID.generate(),
      user: build(:user),
      comment: build(:comment)
    }
  end

  def conversation_factory do
    %Kollective.Chats.Conversation{
      id: Ecto.ULID.generate(),
      title: "My Private Chat Room"
    }
  end

  def chat_participant_factory do
    %Kollective.Chats.Participant{
      id: Ecto.ULID.generate(),
      user: build(:user),
      conversation: build(:conversation),
      public_key: "mock_public_key"
    }
  end

  def chat_message_factory do
    %Kollective.Chats.Message{
      id: Ecto.ULID.generate(),
      encrypted_content: "Encrypted Message Body Content",
      sender_id: Ecto.ULID.generate(),
      conversation: build(:conversation)
    }
  end

  def notification_factory do
    %Kollective.Notifications.Notification{
      id: Ecto.ULID.generate(),
      type: "mention",
      read: false,
      user: build(:user),
      actor: build(:user),
      target_id: Ecto.ULID.generate(),
      target_type: "Post"
    }
  end

  def political_district_factory(attrs) do
    seq = sequence("district_id")

    # Bounding coordinates spanning Austin, TX
    default_geom = %Geo.Polygon{
      coordinates: [
        [
          {-97.75, 30.25},
          {-97.70, 30.25},
          {-97.70, 30.30},
          {-97.75, 30.30},
          {-97.75, 30.25}
        ]
      ],
      srid: 4326
    }

    %Kollective.Locations.PoliticalDistrict{
      name: "State House District #{seq}",
      level: 2,
      type_label: "State Representative",
      state: "TX",
      country: "US",
      external_id: "TX-HD-#{seq}",
      geom: default_geom
    }
    # ExMachina safely overwrites attributes passed by your tests here
    |> merge_attributes(attrs)
  end
end
