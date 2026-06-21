defmodule KollectiveWeb.Router do
  use KollectiveWeb, :router

  import KollectiveWeb.UserAuth

  pipeline :api do
    plug :accepts, ["json"]
    # Automatically reads the Bearer token and assigns :current_scope for all API requests
    plug :fetch_current_scope_for_user
  end

  # Blocks logged-in users from accessing sign-up/login pages
  pipeline :api_unauthenticated do
    plug :redirect_if_user_is_authenticated
  end

  # Enforces an active session token before allowing access
  pipeline :api_authenticated do
    plug :require_authenticated_user
  end

  # Enable Swoosh mailbox preview in development
  if Application.compile_env(:kollective, :dev_routes) do
    scope "/dev" do
      # Change this from :api to your custom browser pipeline if you have one,
      # or leave it empty [] if you do not.
      pipe_through []

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  scope "/api", KollectiveWeb do
    #pipe_through [:api, :ensure_auth]
    pipe_through [:api, :redirect_if_user_is_authenticated]
    get "/me", UserController, :me
  end

  ## Authentication routes

  scope "/api", KollectiveWeb do
    pipe_through [:api, :api_unauthenticated]

    post "/users/register", RegistrationController, :create
  end

  scope "/", KollectiveWeb do
    pipe_through [:api, :require_authenticated_user]

    get "/users/settings", SettingsController, :edit
    put "/users/settings", SettingsController, :update
    get "/users/settings/confirm-email/:token", SettingsController, :confirm_email
  end

  scope "/", KollectiveWeb do
    pipe_through [:api]

    get "/users/log-in", SessionController, :new
    get "/users/log-in/:token", SessionController, :confirm
    post "/users/log-in", SessionController, :create
    delete "/users/log-out", SessionController, :delete
  end

  scope "/api", KollectiveWeb do
    pipe_through :api

    # Endpoint for the React District News page
    get "/districts/:id/news", PoliticalDistrictController, :news
  end

  scope "/api/v1", KollectiveWeb do
    pipe_through :api

    #GET /api/posts  -> Returns the Home Feed.
    #GET /api/v1/posts?scope=state&category=voice&cursor=891-> Returns the Urgent Voice Feed
    get "/posts", PostController, :index

    #GET /api/v1/posts/:id -> Returns the details of a single post, including its nested replies
    get "/posts/:id", PostController, :show

    # Creates a nested route specifically for handling comments/replies under a post
    post "/replies", PostController, :create_reply

    # Interact with an existing poll
    resources "/polls", PollController, only: [:show] do
      post "/votes", PollController, :vote
    end

    # POST 	/api/v1/posts 	Publishes a new post. If poll parameters are included, it attaches the poll.
    # GET	  /api/v1/polls/:id  Returns the current state of a poll (counts, expiry, etc.).
    # POST  	/api/v1/polls/:id/votes 	/api/v1/polls/:id/votes
  end

  scope "/api/v1", KollectiveWeb do
    pipe_through :api

    # Apply rate limiting specifically to the POST action
    #5. Why this is effective for Shadow-Bans

    # Spam Deterrence: Bots often blast keywords to see if they get through. Rate limiting prevents them from testing your keyword list too quickly.
    # Resource Protection: It ensures that a single user cannot fill your oban_jobs or review-queue with thousands of "Pending" posts in seconds.
    # Configurability: You can easily change the "5 posts per minute" threshold based on whether the user is verified or new.

    pipe_through KollectiveWeb.Plugs.RateLimiter

    # Create a post with a poll (handled by PostController)
    post "/posts", PostController,   :create
  end


  scope "/api/v1", KollectiveWeb do
    pipe_through :api

    #GET /api/search?q=peaceful -> Returns the Search Results.
    get "/search", SearchController, :search

    #GET /api/v1/search/accounts?q=superman -> Returns targeted account search results
    get "/search/accounts", SearchController, :account_search

    #GET /api/v1/search/location?q=New+York -> Returns targeted geospatial search results
    get "/search/location", SearchController, :location
  end

  scope "/api/v1", KollectiveWeb do
    pipe_through :api

    # Public endpoint: The React post composer fetches this to populate its picker
    get "/custom_emojis", EmojiController, :index

    # Admin-Protected scope: Protect this scope with your Admin authentication plug
    scope "/admin" do
      # pipe_through :admin_auth

      # Generates the temporary Cloudflare R2 upload ticket
      get "/custom_emojis/presign", Admin.EmojiController, :presign
      # Finalizes the DB record once browser upload succeeds
      post "/custom_emojis", Admin.EmojiController, :create
    end
  end


  # lib/kollective_web/router.ex
  scope "/api/v1", KollectiveWeb do
    pipe_through :api

    # 1. Get a "upload ticket" for R2
    get "/media/presign", MediaController, :presign

    # 2. Finalize the message with the encrypted file metadata
    resources "/conversations/:conversation_id/messages", MessageController, only: [:create]
  end

end
