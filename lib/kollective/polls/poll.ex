# Poll Question is actually the content of the Post the poll is attached to.
# The Answer Choices are stored in the poll_options table

defmodule Kollective.Polls.Poll do
  @moduledoc """
  Schema for polls attached to posts.
  Represents a poll with multiple options that users can vote on.
  """
  use Kollective.Schemas.Schema
  import Ecto.Changeset

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

    timestamps()
  end

  # validation to ensure a poll has between 2 and 4 options, which is the standard Mastodon constraint
  # dd a custom validation to your Poll.changeset. This prevents users from creating "polls" with only one choice or
  # overwhelming the UI with 50 options
  def changeset(poll, attrs) do
    attrs = normalize_attrs(attrs)

    poll
    |> cast(attrs, [:multiple, :expires_at, :non_anonymous])
    |> cast_assoc(:options, required: true, with: &Kollective.Polls.PollOption.changeset/2)
    |> validate_required([:expires_at])
    # <--- Custom validation
    |> validate_options_count()
    # <--- Bonus: Ensure it doesn't expire in the past
    |> validate_future_expiry()
  end

  defp normalize_attrs(attrs) when is_map(attrs) do
    attrs
    |> normalize_expiry()
    |> normalize_options()
  end

  defp normalize_attrs(attrs), do: attrs

  defp normalize_expiry(attrs) do
    has_expires_at =
      (Map.has_key?(attrs, "expires_at") and not is_nil(attrs["expires_at"])) or
        (Map.has_key?(attrs, :expires_at) and not is_nil(attrs[:expires_at]))

    raw_expires_in = attrs["expires_in"] || attrs[:expires_in]

    expires_in =
      cond do
        is_integer(raw_expires_in) and raw_expires_in > 0 ->
          raw_expires_in

        is_binary(raw_expires_in) ->
          case Integer.parse(raw_expires_in) do
            {num, _} when num > 0 -> num
            _ -> nil
          end

        true ->
          nil
      end

    if not has_expires_at and not is_nil(expires_in) do
      future =
        DateTime.utc_now()
        |> DateTime.add(expires_in, :second)
        |> DateTime.truncate(:second)

      if Map.has_key?(attrs, :options) do
        Map.put(attrs, :expires_at, future)
      else
        Map.put(attrs, "expires_at", future)
      end
    else
      attrs
    end
  end

  defp normalize_options(attrs) do
    raw_options = attrs["options"] || attrs[:options]

    if is_list(raw_options) do
      norm_options =
        Enum.map(raw_options, fn
          opt when is_binary(opt) ->
            %{"title" => opt}

          %{text: t} = opt when not is_nil(t) ->
            Map.put(opt, "title", t)

          %{"text" => t} = opt when not is_nil(t) ->
            Map.put(opt, "title", t)

          opt ->
            opt
        end)

      if Map.has_key?(attrs, :options) do
        Map.put(attrs, :options, norm_options)
      else
        Map.put(attrs, "options", norm_options)
      end
    else
      attrs
    end
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
