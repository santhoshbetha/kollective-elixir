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

    # Create a post with a poll (handled by PostController)
    post "/posts", PostController, :create

    # Interact with an existing poll
    resources "/polls", PollController, only: [:show] do
      post "/votes", PollController, :vote
    end

    # POST 	/api/v1/posts 	Publishes a new post. If poll parameters are included, it attaches the poll.
    # GET	/api/v1/polls/:id  Returns the current state of a poll (counts, expiry, etc.).
    # POST  	/api/v1/polls/:id/votes 	/api/v1/polls/:id/votes
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
