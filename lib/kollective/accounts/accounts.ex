defmodule Kollective.Accounts.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Kollective.Repo

  alias Kollective.Accounts.{User, UserToken, UserNotifier}
  alias Kollective.Chats.Participant
  alias Kollective.Accounts.UserRelationship
  alias Kollective.Accounts.UserOrganizationRelationship

  ## Database getters

  @doc """
  Gets a single user by ID.
  Returns nil if the User does not exist.
  """
  def get_user(id) when is_binary(id) or is_integer(id) do
    Repo.get(User, id)
  end

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  # Helper to resolve the @strings into actual User structs:
  def list_users_by_usernames(usernames) do
    User
    |> where([u], u.username in ^usernames)
    |> Repo.all()
  end

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Kollective.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Kollective.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end

  def reset_user_keys(user_id, new_public_key) do
    Repo.transaction(fn ->
      # 1. Update the user's primary public key
      User

      |> where(id: ^user_id)
      |> Repo.update_all(set: [public_key: new_public_key])

      # 2. Update all active conversation participant records
      # This ensures new messages in existing chats use the new key
      from(p in Participant, where: p.user_id == ^user_id)
      |> Repo.update_all(set: [public_key: new_public_key])
    end)
  end

  def update_user_last_seen(user_id, timestamp) do
    from(u in User, where: u.id == ^user_id)
    |> Repo.update_all(set: [last_seen_at: timestamp])
  end

  def get_profile_card(target_id, current_user_id \\ nil) do
    user = Repo.get!(User, target_id)

    # Determine if the active viewer is already following this profile
    is_following =
      if current_user_id do
        Repo.exists?(from r in UserRelationship,
          where: r.source_id == ^current_user_id and r.target_id == ^target_id and r.type == "follow")
      else
        false
      end

    %{
      id: user.id,
      username: user.username,
      avatar_url: user.avatar_url,
      followers_count: user.followers_count, # Direct column read (under 0.5ms)
      following_count: user.following_count, # Direct column read (under 0.5ms)
      is_following: is_following
    }
  end

  @doc """
  Fetches a flat list of user IDs that the given user_id is currently following.
  Optimized to extract raw integers straight from the database index.
  """
  def get_following_ids(user_id) do
    UserRelationship
    |> where([r], r.source_id == ^user_id and r.type == "follow")
    |> select([r], r.target_id)
    |> Repo.all()
  end

  @doc """
  Fetches a flat list of Organization IDs that the given user_id is currently following.
  Optimized to extract raw integers straight from the database index.
  """
  def get_followed_org_ids(user_id) do
    UserOrganizationRelationship
    |> where([r], r.user_id == ^user_id)
    |> select([r], r.organization_id)
    |> Repo.all()
  end

  @doc "Returns a quick boolean if user_a follows user_b"
  def following?(user_a_id, user_b_id) do
     Repo.exists?(
      from r in UserRelationship,
        where: r.source_id == ^user_a_id and r.target_id == ^user_b_id and r.type == "follow"
    )
  end

  # shadow-ban for aggressive spammers
  #Summary of the "Silent" Defense

  #  Bot hits the API 50 times in 10 seconds.
  #  RateLimiter (via Hammer.inspect_bucket) sees the count > 20.
  #  Accounts sets is_shadow_banned: true on that user.
  #  Bot thinks it succeeded (if you return 200) or just keeps trying, but none of its content ever hits the public timeline.
  def flag_user_for_spam("user:" <> user_id) do
    case Repo.get(User, user_id) do
      nil -> {:error, :not_found}
      user ->
        user
        |> User.changeset(%{is_shadow_banned: true})
        |> Repo.update()
    end
  end

  def flag_user_for_spam("ip:" <> _ip), do: :ok # Log IP but can't "ban" a non-user record


end
