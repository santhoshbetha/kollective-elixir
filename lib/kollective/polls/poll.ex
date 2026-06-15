# Poll Question is actually the content of the Post the poll is attached to.
# The Answer Choices are stored in the poll_options table

defmodule Kollective.Polls.Poll do
  @moduledoc """
  Schema for polls attached to posts.
  Represents a poll with multiple options that users can vote on.
  """
  use Kollective.Schemas.Schema

  @type t :: %__MODULE__{}

  schema "polls" do
    field :multiple, :boolean, default: false
    field :non_anonymous, :boolean, default: false
    field :votes_count, :integer, default: 0
    field :expires_at, :utc_datetime
    field :expired, :boolean, default: false

    # Relationships
    belongs_to :post, Kollective.Posts.Post
    has_many :options, Kollective.Polls.PollOption, on_replace: :delete

    # Virtual fields (For React UI)
    field :voted, :boolean, virtual: true, default: false
    field :own_votes, {:array, :integer}, virtual: true, default: []

    timestamps(type: :utc_datetime)
  end

  def changesetX(poll, attrs) do
    poll

    |> cast(attrs, [:multiple, :expires_at, :non_anonymous])
    |> cast_assoc(:options, with: &Kollective.Polls.PollOption.changeset/2, required: true)
    |> validate_required([:expires_at])
  end

  # validation to ensure a poll has between 2 and 4 options, which is the standard Mastodon constraint
  #dd a custom validation to your Poll.changeset. This prevents users from creating "polls" with only one choice or
  #overwhelming the UI with 50 options
  def changeset(poll, attrs) do
    poll

    |> cast(attrs, [:multiple, :expires_at])
    |> cast_assoc(:options, required: true, with: &Kollective.Polls.PollOption.changeset/2)
    |> validate_required([:expires_at])

    |> validate_options_count() # <--- Custom validation
    |> validate_future_expiry() # <--- Bonus: Ensure it doesn't expire in the past
  end

  defp validate_options_count(changeset) do
    # Get the list of options from the changeset
    options = get_change(changeset, :options, [])
    count = length(options)

    cond do
      count < 2 ->
        add_error(changeset, :options, "must have at least 2 choices")
      count > 4 ->
        add_error(changeset, :options, "cannot have more than 4 choices")
      true ->
        changeset
    end
  end

  defp validate_future_expiry(changeset) do
    validate_change(changeset, :expires_at, fn _, expires_at ->
      if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
        []
      else
        [expires_at: "must be in the future"]
      end
    end)
  end

end
