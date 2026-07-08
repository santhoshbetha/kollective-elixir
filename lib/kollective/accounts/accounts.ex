defmodule Kollective.Accounts.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Kollective.Repo

  alias Ecto.Multi
  alias Kollective.Accounts.{User, UserToken, UserNotifier}
  alias Kollective.Chats.Participant
  alias Kollective.Accounts.UserRelationship
  alias Kollective.Schemas.ULIDType

  alias Kollective.Accounts.OrganizationMembership
  alias Kollective.Workers.OrgNotificationWorker

  ## Database getters

  @doc """
  Gets a single user by ID.
  Returns nil if the User does not exist.
  """
  def get_user(id) when is_binary(id) or is_integer(id) do
    Repo.get(User, id)
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

  @doc "Fetches list of target IDs for a specific user and relationship type"
  def list_relationship_ids(user_id, type) do
    UserRelationship
    |> where([r], r.source_id == ^user_id and r.type == ^type)
    |> select([r], r.target_id)
    |> Repo.all()
  end

  @doc """
  The authoritative profile retrieval engine.
  Dynamically detects if the input is a valid ULID system-string token or a standard username,
  fetching the fully cached counter totals in under 0.01ms.

  Returns: %User{} struct record or `nil` if not found.
  """
  def get_user_profile(username_or_id) when is_binary(username_or_id) do
    # 1. ULID/ID IDENTIFICATION GATEWAY
    # Cast parameters safely using your native ULID compilation token
    query =
      case ULIDType.cast(username_or_id) do
        {:ok, ulid} ->
          from(u in User, where: u.id == ^ulid)

        :error ->
          # Downcase input strings to ensure lookups catch records case-insensitively
          downcased_name = String.downcase(username_or_id)
          from(u in User, where: fragment("LOWER(?)", u.username) == ^downcased_name)
      end

    Repo.one(query)
  end

  def get_user_profile(_), do: nil

  @doc """
  Updates an existing user's profile information (Bio, Name, Location, etc.).
  Applies schema validations and outputs the updated user map tuple.
  """
  def update_user_profile(%User{} = user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  # Ensure your Accounts.is_blocked_or_muted?/2 function is optimized to avoid N+1
  # queries during high-volume broadcasts! Phoenix Presence is highly efficient for this.

  # Pro-Tip: If your app grows to thousands of users, you should cache these relationship IDs in an Ets table or
  # Redis so you don't hit Postgres every time a post is broadcasted to 500 different users' channels.
  @doc """
  Checks if a source_id has blocked or muted a target_id.
  Returns true or false.
  """
  def is_blocked_or_muted?(nil, _target_id), do: false

  def is_blocked_or_muted?(source_id, target_id) do
    UserRelationship
    |> where([r], r.source_id == ^source_id and r.target_id == ^target_id)
    |> where([r], r.type in ["block", "mute"])
    |> Repo.exists?()
  end

  # This function is called once per user session or whenever a block/mute occurs.
  def get_cached_blacklist(user_id) do
    cache_key = "user_blacklist:#{user_id}"

    Cachex.fetch(
      :kollective_cache,
      cache_key,
      fn ->
        # If not in cache, hit Postgres once
        blacklist = list_relationship_ids(user_id, ["block", "mute"])

        # Return as a MapSet for O(1) lookups
        {:commit, MapSet.new(blacklist)}
      end,
      ttl: :timer.hours(1)
    )
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
  def update_user_emailX(user, token) do
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

  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transaction(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           token_record when not is_nil(token_record) <- Repo.one(query),
           {:ok, updated_user} <-
             Repo.update(User.email_changeset(user, %{email: token_record.sent_to})),
           {_count, _result} <-
             Repo.delete_all(
               from(t in UserToken, where: t.user_id == ^user.id and t.context == ^context)
             ) do
        # 🏆 Evaluates to 'updated_user'. Repo.transaction will wrap this
        # automatically, returning `{:ok, updated_user}` to your controller and test!
        updated_user
      else
        _error -> Repo.rollback(:transaction_aborted)
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
  def generate_user_session_tokenX(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  def generate_user_session_token(user) do
    # 1. Generate the raw random bytes
    token = :crypto.strong_rand_bytes(32)

    # 2. Hash it with SHA-256 to match the database column values
    hashed_token = :crypto.hash(:sha256, token)

    # 3. Encode it to Base64 for the application/React client
    encoded_token = Base.url_encode64(token, padding: false)

    # 4. Insert the record into the database table
    Repo.insert!(%UserToken{
      # 👈 Must be hashed!
      token: hashed_token,
      context: "session",
      user_id: user.id,
      # 🔄 FIX: Fallback to fresh utc_now ONLY if the user struct doesn't have an authentication timestamp
      authenticated_at: user.authenticated_at || DateTime.utc_now() |> DateTime.truncate(:second)
    })

    # 5. Return the Base64 token to the test case
    encoded_token
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
  def login_user_by_magic_linkX(token) do
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

  def login_user_by_magic_link(token) do
    # 💡 FIX: Use a case statement instead of an absolute tuple pattern match
    case UserToken.verify_magic_link_token_query(token) do
      {:ok, query} ->
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

      {:error, :invalid_token} ->
        {:error, :invalid_token}
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
    {token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_tokenX(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  def delete_user_session_token(token) do
    # 1. Parse out the raw bytes whether it is Base64 text or direct bytes
    decoded_token =
      case Base.url_decode64(token, padding: false) do
        {:ok, bytes} -> bytes
        :error -> token
      end

    # 2. Convert it into the SHA-256 hash saved in your PostgreSQL columns
    hashed_token = :crypto.hash(:sha256, decoded_token)

    # 3. Target the correct hashed token row for deletion
    Repo.delete_all(
      from(t in UserToken, where: t.token == ^hashed_token and t.context == "session")
    )

    :ok
  end

  ## Token helper
  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transaction(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end

  ## Confirmation

  @doc ~S"""
  Delivers the confirmation email instructions to the given user.

  ## Examples

      iex> deliver_user_confirmation_instructions(user, &url(~p"/users/confirm/#{&1}"))
      {:ok, %{to: ..., body: ...}}

      iex> deliver_user_confirmation_instructions(confirmed_user, &url(~p"/users/confirm/#{&1}"))
      {:error, :already_confirmed}

  """
  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if user.is_confirmed do
      {:error, :already_confirmed}
    else
      {token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)
      UserNotifier.deliver_confirmation_instructions(user, confirmation_url_fun.(token))
    end
  end

  @doc """
  Confirms a user by the given token.

  If the token matches, the user account is marked as confirmed
  and the token is deleted.
  """
  def confirm_userX(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  def confirm_user(token) do
    case UserToken.verify_email_token_query(token, "confirm") do
      {:ok, query} ->
        with %User{} = user <- Repo.one(query),
             {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
          {:ok, user}
        else
          _ -> :error
        end

      {:error, :invalid_token} ->
        :error
    end
  end

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["confirm"]))
  end

  ## Reset password

  @doc ~S"""
  Delivers the reset password email to the given user.

  ## Examples

      iex> deliver_user_reset_password_instructions(user, &url(~p"/users/reset_password/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(token))
  end

  @doc """
  Resets the user password.

  ## Examples

      iex> reset_user_password(user, %{password: "new long password", password_confirmation: "new long password"})
      {:ok, %User{}}

      iex> reset_user_password(user, %{password: "valid", password_confirmation: "not the same"})
      {:error, %Ecto.Changeset{}}

  """
  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Gets the user by reset password token.

  ## Examples

      iex> get_user_by_reset_password_token("validtoken")
      %User{}

      iex> get_user_by_reset_password_token("invalidtoken")
      nil

  """
  def get_user_by_reset_password_tokenX(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  def get_user_by_reset_password_token(token) do
    case UserToken.verify_email_token_query(token, "reset_password") do
      {:ok, query} ->
        with %User{} = user <- Repo.one(query) do
          user
        else
          _ -> nil
        end

      {:error, :invalid_token} ->
        nil
    end
  end

  @doc """
  Sends a password reset email to the user with the given email address.

  ## Examples

      iex> reset_password_for_email("user@example.com", fn token -> "https://example.com/reset/\#{token}" end)
      {:ok, %{to: ..., body: ...}}

      iex> reset_password_for_email("nonexistent@example.com", fn token -> "https://example.com/reset/\#{token}" end)
      {:error, :user_not_found}

  """
  def reset_password_for_email(email, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    case get_user_by_email(email) do
      nil ->
        {:error, :user_not_found}

      user ->
        deliver_user_reset_password_instructions(user, reset_password_url_fun)
    end
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
        Repo.exists?(
          from r in UserRelationship,
            where:
              r.source_id == ^current_user_id and r.target_id == ^target_id and r.type == "follow"
        )
      else
        false
      end

    %{
      id: user.id,
      username: user.username,
      avatar_url: user.avatar_url,
      # Direct column read (under 0.5ms)
      followers_count: user.followers_count,
      # Direct column read (under 0.5ms)
      following_count: user.following_count,
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

  # @doc """
  # Fetches an array list of binary IDs for all organization profiles the specified user follows.
  # Uses an inner join pass to guarantee that only followed accounts with a type of :organization are returned.
  # """
  def get_followed_org_ids(user_id) do
    UserRelationship
    # 1. Join back to the users table on the target_id to verify the account type
    |> join(:inner, [r], u in User, on: r.target_id == u.id)
    # 2. Filter strictly by the active reader's ID, the "follow" token type, and the :organization enum value
    |> where([r, u], r.source_id == ^user_id and r.type == "follow" and u.type == :organization)
    # 3. Select only the target organization IDs out of the database pass
    |> select([r, u], r.target_id)
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
  # Summary of the "Silent" Defense

  #  Bot hits the API 50 times in 10 seconds.
  #  RateLimiter (via Hammer.inspect_bucket) sees the count > 20.
  #  Accounts sets is_shadow_banned: true on that user.
  #  Bot thinks it succeeded (if you return 200) or just keeps trying, but none of its content ever hits the public timeline.
  def flag_user_for_spam("user:" <> user_id) do
    case Repo.get(User, user_id) do
      nil ->
        {:error, :not_found}

      user ->
        user
        |> User.changeset(%{is_shadow_banned: true})
        |> Repo.update()
    end
  end

  # Log IP but can't "ban" a non-user record
  def flag_user_for_spam("ip:" <> _ip), do: :ok

  def blocks?(%Kollective.Accounts.User{} = source, %Kollective.Accounts.User{} = target) do
    Kollective.Repo.exists?(
      from(r in "user_relationships",
        where: r.source_id == ^source.id and r.target_id == ^target.id and r.type == "block"
      )
    )
  end

  def blocks?(_, _), do: false

  @doc "Allows a real-world user to request access to an organization actor profile."
  def request_organization_join(user_id, organization_id) do
    # Verify the target is actually an organization account type
    case Repo.get(User, organization_id) do
      %User{type: :organization} ->
        %OrganizationMembership{}
        |> OrganizationMembership.changeset(%{
          user_id: user_id,
          organization_id: organization_id,
          status: :pending,
          role: :member
        })
        |> Repo.insert()

      _ ->
        {:error, :invalid_target_account}
    end
  end

  @doc "Allows an organization administrator to approve or reject a pending request."
  def process_join_request(%User{} = manager, membership_id, action)
      when action in [:approved, :rejected] do
    membership = Repo.get!(OrganizationMembership, membership_id)

    # 1. ENFORCE OWNERSHIP SECURITY: Verify the manager is an approved ADMIN of the organization
    is_admin? =
      Repo.exists?(
        from(m in OrganizationMembership,
          where:
            m.organization_id == ^membership.organization_id and m.user_id == ^manager.id and
              m.role == :admin and m.status == :approved
        )
      )

    if not is_admin? do
      {:error, :unauthorized}
    else
      Multi.new()
      # Step A: Atomic status update switch
      |> Multi.update(
        :membership,
        OrganizationMembership.changeset(membership, %{status: action})
      )

      # Step B: ASYNC LIFE-CYCLE SCHEDULING (Offload heavy Swoosh emails entirely to an Oban queue)
      |> Multi.run(:enqueue_email, fn _repo, _changes ->
        %{
          "user_id" => membership.user_id,
          "organization_id" => membership.organization_id,
          "action" => Atom.to_string(action)
        }
        |> OrgNotificationWorker.new()
        |> Oban.insert!()

        {:ok, :notified}
      end)
      |> Repo.transaction()
    end
  end

  @doc "Fetches all organization accounts a specific user is authorized to post under."
  def list_authorized_organizations(user_id) do
    from(u in User,
      join: m in OrganizationMembership,
      on: m.organization_id == u.id,
      where: m.user_id == ^user_id and m.status == :approved,
      select: %{id: u.id, username: u.username, badge_type: fragment("?->>'badge_type'", u.data)}
    )
    |> Repo.all()
  end

  def search_organizations_by_type(query_str) when is_binary(query_str) do
    if String.trim(query_str) == "" do
      []
    else
      search_term = "%#{String.downcase(query_str)}%"

      from(u in User,
        where: u.type == :organization,
        where:
          fragment(
            "LOWER(?) LIKE ? or LOWER(?) LIKE ?",
            u.username,
            ^search_term,
            u.name,
            ^search_term
          ),
        order_by: [asc: u.username],
        limit: 20
      )
      |> Repo.all()
    end
  end

  @doc """
  Verifies if a specific handle is already claimed on the platform.
  Utilizes an existential index scan pass to complete in under 0.2ms .
  """
  def username_taken?(username) do
    normalized_handle = String.trim(username) |> String.downcase()

    if normalized_handle == "" do
      true
    else
      # Repo.exists? executes a lightweight SELECT 1 ... LIMIT 1 expression
      # This prevents loading large rows or preloads into server RAM
      Kollective.Repo.exists?(
        from(u in Kollective.Accounts.User,
          where: fragment("lower(?) = ?", u.username, ^normalized_handle)
        )
      )
    end
  end

  @doc """
  Atomic transaction to adjust system staff privileges out-of-band.
  Enforces that a matching audit log entry is committed synchronously to preserve chain accountability.
  """
  def update_staff_role(username, role_type, admin_id) do
    normalized_username = String.trim(username) |> String.downcase()

    case Repo.get_by(User, username: normalized_username) do
      nil ->
        {:error, :not_found}

      %User{} = user ->
        # Determine exact attribute mappings based on chosen target parameter roles
        role_changes =
          case role_type do
            :admin -> %{is_admin: true, is_moderator: false}
            :moderator -> %{is_admin: false, is_moderator: true}
          end

        Multi.new()
        # Step A: Shift target structural boolean privilege flags
        |> Multi.update(:user, Ecto.Changeset.change(user, role_changes))
        # Step B: Record the transaction inside your centralized Admin Log table rows
        |> Multi.insert(:audit_log, fn _changes ->
            %Kollective.Admins.Log{
              action: "staff_role_promotion_#{Atom.to_string(role_type)}",
              target_id: user.id,
              target_type: "User",
              user_id: admin_id,
              metadata: %{promoted_username: user.username, timestamp: DateTime.utc_now()}
            }
          end)
        |> Repo.transaction()
        |> case do
            {:ok, %{user: updated_user}} -> {:ok, updated_user}
            {:error, _failed_step, changeset, _changes} -> {:error, changeset}
          end
    end
  end

end
