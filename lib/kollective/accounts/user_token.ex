defmodule Kollective.Accounts.UserToken do
  use Kollective.Schemas.Schema
  import Ecto.Query
  alias Kollective.Accounts.UserToken

  @rand_size 32

  # It is very important to keep the magic link token expiry short,
  # since someone with access to the email may take over the account.
  @magic_link_validity_in_minutes 15
  @reset_password_validity_in_days 1
  @confirm_validity_in_days 7
  @change_email_validity_in_days 7
  @session_validity_in_days 14

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    field :authenticated_at, :utc_datetime
    belongs_to :user, Kollective.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Generates a token that will be stored in a signed place,
  such as session or cookie. As they are signed, those
  tokens do not need to be hashed.

  The reason why we store session tokens in the database, even
  though Phoenix already provides a session cookie, is because
  Phoenix's default session cookies are not persisted, they are
  simply signed and potentially encrypted. This means they are
  valid indefinitely, unless you change the signing/encryption
  salt.

  Therefore, storing them allows individual user
  sessions to be expired. The token system can also be extended
  to store additional data, such as the device used for logging in.
  You could then use this information to display all valid sessions
  and devices in the UI and allow users to explicitly expire any
  session they deem invalid.
  """
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    dt = user.authenticated_at || DateTime.utc_now(:second)

    {token,
     %UserToken{
       token: token,
       context: "session",
       user_id: user.id,
       authenticated_at: dt
     }}
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the user found by the token, if any.

  The given token is valid if it matches its hashed counterpart in the
  database and the user email has not changed. This function also checks
  if the token is being used within a certain period, depending on the
  context. The default contexts supported by this function are either
  "confirm", for account confirmation emails, and "reset_password",
  for resetting the password. For verifying requests to change the email,
  see `verify_change_email_token_query/2`.
  """
  def verify_email_token_queryX(token, context) do
    days = days_for_context(context)

    query =
      from token in by_token_and_context_query(token, context),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(^days, "day") and token.sent_to == user.email,
        select: user

    {:ok, query}
  end

  def verify_email_token_query(token, context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(:sha256, decoded_token)
        days = days_for_context(context)

        # ➕ Step 1: Calculate the absolute cutoff timestamp using native Elixir time functions
        cutoff_date = DateTime.utc_now() |> DateTime.add(-days, :day)

        query =
          from token in by_token_and_context_query(hashed_token, context),
            join: user in assoc(token, :user),
            # 💡 Step 2: Use a standard comparison with the pin operator ^
            where: token.inserted_at > ^cutoff_date and token.sent_to == user.email,
            select: user

        {:ok, query}

      :error ->
        {:error, :invalid_token}
    end
  end

  defp days_for_context("confirm"), do: @confirm_validity_in_days
  defp days_for_context("reset_password"), do: @reset_password_validity_in_days

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the user found by the token, if any, along with the token's creation time.

  The token is valid if it matches the value in the database and it has
  not expired (after @session_validity_in_days).
  """
  def verify_session_token_queryX(token) do
    query =
      from token in by_token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: {%{user | authenticated_at: token.authenticated_at}, token.inserted_at}

    {:ok, query}
  end

  def verify_session_token_query(token) when is_binary(token) do
    decoded_token =
      cond do
        byte_size(token) == 32 ->
          token

        true ->
          case Base.url_decode64(token, padding: false) do
            {:ok, bytes} -> bytes
            :error -> token
          end
      end

    hashed_token = :crypto.hash(:sha256, decoded_token)

    query =
      from token in UserToken,
        where:
          token.token == ^hashed_token and
            (token.context == "session" or like(token.context, "session:org:%")),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: {%{user | authenticated_at: token.authenticated_at}, token.inserted_at}

    {:ok, query}
  end

  @doc """
  Checks if the session token is valid and returns user, inserted_at, and context tuple.
  """
  def verify_session_token_and_context_query(token) when is_binary(token) do
    decoded_token =
      cond do
        byte_size(token) == 32 ->
          token

        true ->
          case Base.url_decode64(token, padding: false) do
            {:ok, bytes} -> bytes
            :error -> token
          end
      end

    hashed_token = :crypto.hash(:sha256, decoded_token)

    query =
      from token in UserToken,
        where:
          token.token == ^hashed_token and
            (token.context == "session" or like(token.context, "session:org:%")),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select:
          {%{user | authenticated_at: token.authenticated_at}, token.inserted_at, token.context}

    {:ok, query}
  end

  @doc """
  Builds a token and its hash to be delivered to the user's email.

  The non-hashed token is sent to the user email while the
  hashed part is stored in the database. The original token cannot be reconstructed,
  which means anyone with read-only access to the database cannot directly use
  the token in the application to gain access. Furthermore, if the user changes
  their email in the system, the tokens sent to the previous email are no longer
  valid.

  Users can easily adapt the existing code to provide other types of delivery methods,
  for example, by phone numbers.
  """
  def build_email_token(user, context) do
    build_token(user, context, user.email)
  end

  defp build_token(user, context, sent_to) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(:sha256, token)
    encoded_token = Base.url_encode64(token, padding: false)

    {encoded_token,
     %UserToken{
       token: hashed_token,
       context: context,
       sent_to: sent_to,
       user_id: user.id
     }}
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  If found, the query returns a tuple of the form `{user, token}`.

  The given token is valid if it matches its hashed counterpart in the
  database. This function also checks if the token is being used within
  15 minutes. The context of a magic link token is always "login".
  """
  def verify_magic_link_token_queryX(token) do
    query =
      from token in by_token_and_context_query(token, "login"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(^@magic_link_validity_in_minutes, "minute"),
        where: token.sent_to == user.email,
        select: {user, token}

    {:ok, query}
  end

  def verify_magic_link_token_query(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(:sha256, decoded_token)

        query =
          from token in by_token_and_context_query(hashed_token, "login"),
            join: user in assoc(token, :user),
            # 💡 FIX: Pass the module attribute directly to ago/2 WITHOUT the pin operator
            where: token.inserted_at > ago(@magic_link_validity_in_minutes, "minute"),
            where: token.sent_to == user.email,
            select: {user, token}

        {:ok, query}

      :error ->
        # 💡 FIX: Return a structured error tuple so your caller doesn't crash on bad inputs
        {:error, :invalid_token}
    end
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the user_token found by the token, if any.

  This is used to validate requests to change the user
  email.
  The given token is valid if it matches its hashed counterpart in the
  database and if it has not expired (after @change_email_validity_in_days).
  The context must always start with "change:".
  """
  def verify_change_email_token_queryX(token, "change:" <> _ = context) do
    query =
      from token in by_token_and_context_query(token, context),
        where: token.inserted_at > ago(@change_email_validity_in_days, "day")

    {:ok, query}
  end

  def verify_change_email_token_query(token, "change:" <> _ = context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(:sha256, decoded_token)

        query =
          from token in by_token_and_context_query(hashed_token, context),
            # 💡 FIX: Join the user association so we can return the User record
            join: user in assoc(token, :user),
            where: token.inserted_at > ago(@change_email_validity_in_days, "day"),
            select: token

        {:ok, query}

      :error ->
        # 💡 FIX: Return a structured error tuple to prevent runtime server crashes
        {:error, :invalid_token}
    end
  end

  defp by_token_and_context_query(token, context) do
    # Hash the incoming token bytes using SHA-256 to match the database values
    # hashed_token = :crypto.hash(:sha256, token)
    from UserToken, where: [token: ^token, context: ^context]
  end

  @doc """
  Gets all tokens for the given user for the given contexts.
  """
  def by_user_and_contexts_query(user, :all) do
    from t in UserToken, where: t.user_id == ^user.id
  end

  def by_user_and_contexts_query(user, [_ | _] = contexts) do
    from t in UserToken, where: t.user_id == ^user.id and t.context in ^contexts
  end
end
