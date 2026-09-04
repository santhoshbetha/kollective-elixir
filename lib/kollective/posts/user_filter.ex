# lib/kollective/posts/user_filter.ex
defmodule Kollective.Posts.UserFilter do
  use Kollective.Schemas.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Kollective.Repo
  alias Kollective.Accounts.User

  schema "user_filters" do
    field :phrase, :string
    field :whole_word, :boolean, default: true
    field :context, {:array, :string}, default: ["home", "public"]
    field :expires_at, :utc_datetime

    belongs_to :user, User, foreign_key: :user_id
    timestamps()
  end

  def changeset(filter, attrs) do
    filter
    |> cast(attrs, [:phrase, :whole_word, :context, :expires_at, :user_id])
    |> validate_required([:phrase, :context, :user_id])
    |> validate_length(:phrase, min: 1, max: 100)
    # Replaces complex max counter loops with an atomic unique constraint guard index
    |> unique_constraint([:user_id, :phrase], name: :user_filters_phrase_unique_index)
    |> cast_expiry_duration(attrs)
  end

  defp cast_expiry_duration(changeset, %{"expires_in" => expires_in})
       when is_integer(expires_in) and expires_in > 0 do
    expires_at =
      DateTime.utc_now() |> DateTime.add(expires_in, :second) |> DateTime.truncate(:second)

    put_change(changeset, :expires_at, expires_at)
  end

  defp cast_expiry_duration(changeset, %{expires_in: expires_in})
       when is_integer(expires_in) and expires_in > 0 do
    expires_at =
      DateTime.utc_now() |> DateTime.add(expires_in, :second) |> DateTime.truncate(:second)

    put_change(changeset, :expires_at, expires_at)
  end

  defp cast_expiry_duration(changeset, _), do: changeset

  # ─── CORE QUERY INTERFACES ───

  def list_active_filters(%User{id: user_id}) do
    now = DateTime.utc_now()

    from(f in __MODULE__,
      where: f.user_id == ^user_id,
      where: is_nil(f.expires_at) or f.expires_at > ^now,
      order_by: [desc: f.id]
    )
    |> Repo.all()
  end

  def get_user_filter(id, %User{id: user_id}) do
    Repo.get_by(__MODULE__, id: id, user_id: user_id)
  end

  # ─── HIGH-SPEED REGEX COMPILER PASS ───

  def compile_regex_pattern(filters) when is_list(filters) do
    if filters == [] do
      nil
    else
      # Escape special characters to prevent regex injection attacks
      phrases =
        filters
        |> Enum.map(&Regex.escape(&1.phrase))
        |> Enum.join("|")

      # Compiles a single regex pattern matching word boundaries natively
      ~r/\b(#{phrases})\b/i
    end
  end
end
