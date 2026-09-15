defmodule KollectiveWeb.Router do
  use KollectiveWeb, :router

  import KollectiveWeb.UserAuth

  pipeline :api do
    plug :accepts, ["json"]

    # 1. READS THE BEARER TOKEN: Decodes and populates :current_user directly in RAM
    # This makes current_user instantly available to both public and private routes
    # plug KollectiveWeb.Plugs.APIAuth

    # 2. OPTIONAL: Leave your old scope fetcher here if it builds other oauth properties
    # plug :fetch_current_scope_for_user
  end

  # Enforces an active session token before allowing access
  pipeline :api_authenticated do
    # 1. First, decode the Bearer token header and assign :current_user
    plug KollectiveWeb.Plugs.APIAuth

    # 2. Second, run the helper to map :current_user onto the structural domain :current_scope
    plug :fetch_current_scope_for_user
    plug :require_authenticated_user
  end

  # Identifies whether the request context is a personal account or an org
  pipeline :org_context do
    plug KollectiveWeb.Plugs.AssignOrganization
  end

  # Strictly enforces that the request MUST have an active organization context
  pipeline :require_org do
    # Simple plug checking if conn.assigns.current_org_id != nil
    plug KollectiveWeb.Plugs.RequireActiveOrganization
  end

  # Blocks the request if the user is not an Admin or Owner of the active org
  pipeline :require_org_admin do
    plug KollectiveWeb.Plugs.RequireOrgAdmin
  end

  pipeline :api_rate_limited do
    # Direct-to-RAM sliding window gateway blocks bots before hitting controllers
    plug KollectiveWeb.Plugs.RateLimiter
  end

  # SECURE GOVERNANCE PIPELINE
  pipeline :require_admin_authenticated do
    # Step 3: Enforces that the logged-in user possesses administrative privileges
    plug KollectiveWeb.Plugs.RequireAdminAuthenticated
  end

  # Blocks logged-in users from accessing sign-up/login pages
  pipeline :api_unauthenticated do
    plug :redirect_if_user_is_authenticated
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

  scope "/api/v1", KollectiveWeb do
    pipe_through [:api, :api_authenticated]

    get "/me", UserController, :me
    post "/clear-feed-badge", UserController, :clear_feed_badge

    put "/user/location", UserController, :update_location
    patch "/user/location", UserController, :update_location
    put "/me/political-location", UserController, :update_location
    patch "/me/political-location", UserController, :update_location
    delete "/user/location", UserController, :delete_location
  end

  scope "/api", KollectiveWeb do
    pipe_through [:api, :api_authenticated]

    get "/me", UserController, :me
    put "/me/political-location", UserController, :update_location
    patch "/me/political-location", UserController, :update_location
  end

  scope "/api/v1", KollectiveWeb do
    # Public pipeline (No require_authenticated_user plug)
    pipe_through [:api]

    # 🚀 REAL-TIME REGISTRATION AVAILABILITY CHECKER
    get "/auth/check-username", AuthController, :check_username

    # 📢 Town Bulletin / Classifieds Directory (Public)
    get "/classifieds", ClassifiedController, :index
    get "/classifieds/:id", ClassifiedController, :show
  end

  scope "/api/users", KollectiveWeb do
    pipe_through [:api, :api_unauthenticated]

    post "/", RegistrationController, :create
    post "/register", RegistrationController, :create
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete

    post "/reset_password", ResetPasswordController, :create
    put "/reset_password/:token", ResetPasswordController, :update

    post "/resend_confirmation", ConfirmationController, :resend
    post "/confirm/:token", ConfirmationController, :confirm
  end

  scope "/api/v1", KollectiveWeb do
    pipe_through [:api, :api_authenticated]

    get "/accounts/:username_or_id", ProfileController, :show

    # Accessible account profiles (personal + active orgs)
    get "/profiles", ProfileController, :index_profiles

    # Media upload presignment tickets
    get "/profile/media/presign", ProfileController, :presign_asset

    # Main profile parameters modifier mapping
    put "/profile", ProfileController, :update

    get "/profile/authorized_organizations", ProfileController, :list_authorized_organizations
  end

  scope "/api/v1", KollectiveWeb do
    pipe_through [:api, :api_authenticated]

    # 📢 Town Bulletin / Classifieds Post & Management
    post "/classifieds", ClassifiedController, :create
    delete "/classifieds/:id", ClassifiedController, :delete
  end

  scope "/api/v1", KollectiveWeb do
    pipe_through [:api, :api_authenticated]

    # List blocked/muted user indices for the settings panels
    get "/relationships", RelationshipController, :index

    # Single universal button toggle route handling follow, block, and mutes uniformly
    post "/relationships/toggle", RelationshipController, :toggle
  end

  ## Authentication routes
  scope "/api/v1", KollectiveWeb do
    pipe_through [:api, :api_authenticated]

    get "/users/settings", SettingsController, :edit
    put "/users/settings", SettingsController, :update
    get "/users/settings/confirm-email/:token", SettingsController, :confirm_email
  end

  scope "/api/v1", KollectiveWeb do
    pipe_through [:api, :api_authenticated]

    # Public Search and Request Pipelines
    get "/organizations/search", OrganizationController, :search
    post "/organizations/:org_id/join", OrganizationController, :join_request

    # Internal Corporate Governance Panels
    get "/organizations/:org_id/requests", OrganizationAdminController, :pending_members

    post "/organization_requests/:membership_id/process",
         OrganizationAdminController,
         :update_status

    post "/organizations/:org_id/members/:user_id/role", OrganizationAdminController, :change_role
  end

  # =========================================================================
  # SCOPE 1: Personal User Account Operations
  # No organization context headers are needed here.
  # =========================================================================
  scope "/api", KollectiveWeb do
    pipe_through [:api, :api_authenticated]

    # Handled by InvitationController
    get "/invitations", InvitationController, :index
    post "/invitations/:id/accept", InvitationController, :accept
    post "/invitations/:id/decline", InvitationController, :decline

    get "/profiles", ProfileController, :index_profiles
  end

  scope "/api/v1", KollectiveWeb do
    pipe_through [:api, :api_authenticated]

    # Handled by InvitationController (v1 alias)
    get "/invitations", InvitationController, :index
    post "/invitations/:id/accept", InvitationController, :accept
    post "/invitations/:id/decline", InvitationController, :decline
  end

  # =========================================================================
  # SCOPE 2: General Team & Roster Operations
  # Requires a valid active organization context header.
  # =========================================================================
  scope "/api/v1/org-settings", KollectiveWeb do
    # Enforces authentication, valid org membership, AND admin/owner status ranks
    pipe_through [:api, :api_authenticated, :org_context, :require_org]

    # Handled by TeamController
    get "/members", TeamController, :index
    delete "/members/:user_id", TeamController, :remove_member

    # Handled by AuditLogController (from previous step)
    get "/audit-logs", AuditLogController, :index

    # endpoint to fulfill the React TeamManagement.jsx fetching requirement
    get "/pending-invites", TeamController, :pending_invites
  end

  # =========================================================================
  # SCOPE 3: High-Level Administrative Operations
  # Requires admin or owner privileges within that specific organization.
  # =========================================================================
  scope "/api/v1/org-admin", KollectiveWeb do
    pipe_through [:api, :api_authenticated, :org_context, :require_org, :require_org_admin]

    # Handled by OrganizationController
    post "/transfer-ownership", OrganizationController, :transfer_ownership
    post "/organizations/:org_id/invite", OrganizationController, :invite_contributor

    post "/organizations/:org_id/invite/:invite_id/resend", OrganizationController, :resend_invite
    delete "/organizations/:org_id/invite/:invite_id", OrganizationController, :remove_invite
  end

  scope "/api/v1", KollectiveWeb do
    pipe_through [:api, :api_authenticated]

    # Endpoint for the React District News page
    get "/districts/:id/news", PoliticalDistrictController, :news
  end

  scope "/api/v1", KollectiveWeb do
    pipe_through [:api, :api_authenticated]

    # GET /api/v1/posts  -> Returns the Home Feed.
    # GET /api/v1/posts?scope=state&category=voice&cursor=891-> Returns the Urgent Voice Feed
    get "/posts", PostController, :index

    # GET /api/v1/posts/:id -> Returns the details of a single post, including its nested replies
    # GET /api/v1/posts?q=peaceful -> Returns the Search Results.
    # GET /api/v1/posts?category=voice -> Returns the Urgent Voice Feed
    get "/posts/:id", PostController, :show
    put "/posts/:id", PostController, :update
    delete "/posts/:id", PostController, :delete

    # Creates a nested route specifically for handling comments/replies under a post
    post "/replies", PostController, :create_reply

    # /api/v1/posts/:id/reblog -> Reblogs the specified post on behalf of the current user (boost)
    post "/posts/:id/reblog", PostController, :handle_reblog

    # /api/v1/posts/:id/like -> Toggles the like status for the specified post on behalf of the current user
    post "/posts/:id/like", PostController, :handle_like
  end

  # ─── SCOPE C: PROTECTED WRITE MUTATIONS & EXPENSIVE LOOKUPS ───
  # Moderation endpoints (post restoration)
  scope "/api/v1", KollectiveWeb.Admin do
    pipe_through [:api, :api_authenticated, :api_rate_limited]

    post "/admin/posts/:id/restore", ModerationController, :restore_post
    post "/admin/posts/:id/reject", ModerationController, :reject_post
    post "/admin/posts/:id/appeal", ModerationController, :appeal_post
    delete "/admin/posts/:id/kill", ModerationController, :kill_post

    post "/admin/posts/bulk_approve", ModerationController, :bulk_approve
  end

  # ─── SCOPE B: PROTECTED WRITE MUTATIONS & EXPENSIVE LOOKUPS ───
  # These endpoints pass through the rate limiter plug to completely shield the database
  scope "/api/v1", KollectiveWeb do
    pipe_through [:api, :api_authenticated, :api_rate_limited]

    # Post Creations & Responses
    # POST /api/v1/posts -> Creates a new post, optionally with a poll attached.
    # If the user is shadow-banned, the post will be created but not visible to others.
    # Apply rate limiting specifically to the POST action
    # Why this is effective for Shadow-Bans

    # Spam Deterrence: Bots often blast keywords to see if they get through. Rate limiting prevents them from testing your keyword list too quickly.
    # Resource Protection: It ensures that a single user cannot fill your oban_jobs or review-queue with thousands of "Pending" posts in seconds.
    # Configurability: You can easily change the "5 posts per minute" threshold based on whether the user is verified or new.

    post "/posts", PostController, :create

    # /api/v1/posts/:id/replies -> Creates a new reply to the specified post, with content and optional image
    post "/posts/:id/replies", PostController, :create_reply
    post "/posts/:post_id/bookmark", BookmarkController, :toggle

    # Grassroots Registrations & Launch Wizards
    post "/businesses", BusinessController, :create
    post "/business_proposals", BusinessController, :create_proposal
    # Wizard Terminal Trigger (Step 2 "Launch Action" Button Click)
    # POST /api/v1/actions
    # JSON Payload Body fields: %{"action" => %{"name" => "Action Title", "category" => "protest", ...}}
    post "/actions", ActionController, :create
    post "/events", EventController, :create

    # Interactive Chat Threads & Media Presigns
    post "/events_comments/:event_id/comment", EventCommentController, :create
    get "/event_comments/image/presign", EventCommentController, :presign_image
    get "/media/presign", MediaController, :presign

    # Governance Flags & Geo-Service Handshakes
    # Regular citizens can report posts safely here
    post "/posts/:post_id/report", ReportController, :create
    patch "/profile/districts", UserController, :update_districts
  end

  scope "/api/v1", KollectiveWeb do
    pipe_through [:api, :api_authenticated]

    # ─── 🏷️ FRONTEND-COMPLIANT QUERY STRING HASHTAG REPO ───
    # GET /api/discovery/hashtag?tag=grassroots&cursor=01J0A...&category=voice
    get "/discovery/hashtag", HashtagController, :show_by_query

    # ─── 🏷️ HASHTAG TIMELINE DISCOVERY STREAM ───
    get "/timelines/tag/:tag", HashtagController, :show

    # ─── 📰 USER FEEDS & TIMELINES ───
    get "/timeline/home", FeedController, :home
    get "/communities/feed", FeedController, :feed
    get "/trending/tags", TrendingController, :index
  end

  scope "/api/v1", KollectiveWeb do
    pipe_through [:api, :api_authenticated]

    # User Mute Phrase Curation Directories
    get "/filters", FilterController, :index
    post "/filters", FilterController, :create
    delete "/filters/:id", FilterController, :delete_filter
  end

  scope "/api/v1", KollectiveWeb do
    pipe_through [:api, :api_authenticated]

    # Bookmark Timeline Feed & Action Switches
    get "/bookmarks", BookmarkController, :index
  end

  scope "/api/v1", KollectiveWeb do
    pipe_through [:api, :api_authenticated, :api_rate_limited]

    # Timeline Post Emoji Reaction Toggles
    post "/posts/:post_id/reactions", PostReactionController, :create
  end

  scope "/api/v1", KollectiveWeb do
    pipe_through [:api, :api_authenticated]

    # Interact with an existing poll
    get "/polls/:id", PollController, :show
    post "/polls/:poll_id/votes", PollController, :vote

    # POST 	/api/v1/posts 	Publishes a new post. If poll parameters are included, it attaches the poll.
    # GET	  /api/v1/polls/:id  Returns the current state of a poll (counts, expiry, etc.).
    # POST  /api/v1/polls/:id/votes 	/api/v1/polls/:id/votes
  end

  scope "/api/v1", KollectiveWeb do
    # Ensure user is logged in
    pipe_through [:api, :api_authenticated]

    get "/events", EventController, :index
    get "/events/joined", EventController, :joined_events
    get "/events/nearby", EventController, :nearby
    post "/events/filter_by_date", EventController, :filter_by_date
    get "/events/:id", EventController, :show

    put "/events/:id", EventController, :update

    delete "/events/:id", EventController, :delete

    post "/events/:id/invite", EventController, :invite
  end

  scope "/api/v1", KollectiveWeb do
    pipe_through [:api, :api_authenticated]

    get "/events/:event_id/media/presign", EventMediaController, :presign_upload
    get "/events/:event_id/media", EventMediaController, :index
    delete "/events/media/:comment_id/hide", EventMediaController, :hide
  end

  scope "/api/v1", KollectiveWeb do
    pipe_through [:api, :api_authenticated]

    # React UI Query Toggles: ?category=town_hall&scope=state
    get "/actions", ActionController, :index

    # GET /api/v1/events/:id
    # Feeds individual protest, meeting, rally, or town hall detail pages
    get "/actions/:id", EventController, :show

    # 4. Action Logistics & Time Remodifier Engine
    # PUT /api/v1/actions/:id
    # Wipes and updates Oban countdown reminder queues automatically on date updates
    put "/actions/:id", EventController, :update
  end

  scope "/api/v1", KollectiveWeb do
    # Ensure user is logged in
    pipe_through [:api, :api_authenticated]

    get "/event_comments", EventCommentController, :index
    get "/event_comments/:id", EventCommentController, :show

    post "/event_comments/:comment_id/like", EventCommentController, :like
  end

  scope "/api/v1", KollectiveWeb do
    # Ensure user is logged in
    pipe_through [:api, :api_authenticated]

    get "/businesses", BusinessController, :index
    get "/business_proposals", BusinessController, :index

    # Individual Detail View Mappings
    get "/businesses/:id", BusinessController, :show_business
    get "/business_proposals/:id", BusinessController, :show_proposal
    put "/businesses/:id", BusinessController, :update
    delete "/businesses/:id", BusinessController, :delete_business

    # Map both methods directly to the exact same controller function
    put "/business_proposals/:id", BusinessController, :update_proposal
    patch "/business_proposals/:id", BusinessController, :update_proposal
    delete "/business_proposals/:id", BusinessController, :delete_proposal
  end

  scope "/api/v1", KollectiveWeb do
    pipe_through [:api, :api_authenticated]

    # GET /api/search?q=peaceful -> Returns the Search Results.
    # 1. Unified Omnibox Lookup (Runs parallel streams over all components)
    # React URL: /api/v1/search?q=austin
    # React Tab Override URL: /api/v1/search?q=austin&type=events
    get "/search", SearchController, :search

    # GET /api/v1/search/accounts?q=superman -> Returns targeted account search results
    # 2. Targeted Accounts Dropdown Picker Autocomplete
    # React URL: /api/v1/search/accounts?q=alice&following=true
    get "/search/accounts", SearchController, :account_search

    # GET /api/v1/search/location?q=New+York -> Returns targeted geospatial search results
    get "/search/location", SearchController, :location
  end

  scope "/api/v1", KollectiveWeb do
    pipe_through [:api, :api_authenticated]

    # Endpoint for jurors to securely post their decision
    post "/voting/applications/:application_id/votes", JuryVoteController, :cast_vote

    post "/scholar-verify", ScholarController, :verify_orcid
    post "/journalist-verify", JournalistController, :verify_portfolio
  end

  # SECURE MODERATION DESK PANEL OVERRIDES
  scope "/api/v1/admin", KollectiveWeb.Admin do
    pipe_through [:api, :api_authenticated, :require_admin_authenticated]

    # Restrictive overrides reserved strictly for staff members
    post "/reports/:id/resolve", ReportController, :resolve
    post "/reports/:report_id/kill", ReportController, :kill_flagged_event

    get "/audit_logs", LogController, :index
  end

  scope "/api/v1/admin", KollectiveWeb.Admin do
    # Multi-tier gateway filter chain protects these routes from user-spoofing attacks
    pipe_through [:api, :api_authenticated, :require_admin_authenticated]

    # RAM IP Blacklist Monitoring Panel Lookups
    get "/security/blacklist", SecurityController, :index
    delete "/security/blacklist/:ip", SecurityController, :pardon

    # Bulk Cooldown Wipes
    post "/security/lift-cooldowns", SecurityController, :lift_all

    # Emergency Kill Switch Actions
    post "/security/lockdown/enable", SecurityController, :enable_lockdown
    post "/security/lockdown/disable", SecurityController, :disable_lockdown
  end

  scope "/api/v1", KollectiveWeb do
    pipe_through [:api, :api_authenticated]

    # Public endpoint: The React post composer fetches this to populate its picker
    # api/v1/custom_emojis
    get "/custom_emojis", EmojiController, :index
  end

  # Admin-Protected scope: Protect this scope with your Admin authentication plug
  scope "/api/v1/admin", KollectiveWeb.Admin do
    pipe_through [:api, :api_authenticated, :require_admin_authenticated]

    # Generates the temporary Cloudflare R2 upload ticket
    # GET /api/v1/admin/custom_emojis/presign
    get "/custom_emojis/presign", AdminEmojiController, :presign

    # Finalizes the DB record once browser upload succeeds
    # POST /api/v1/admin/custom_emojis
    post "/custom_emojis", AdminEmojiController, :create
  end

  # 🛠️ Protected Central Administration Scope
  scope "/api/v1/admin/civic", KollectiveWeb.Admin do
    # pipe_through [:api, :authenticate_user, :enforce_admin_clearance]
    pipe_through [:api, KollectiveWeb.Plugs.APIAuth, KollectiveWeb.Plugs.AdminAuth]

    # Video check override bootstrap manual tool endpoint
    post "/bootstrap-seed", VouchBootstrapController, :bootstrap_seed
  end

  # 👥 Public Peer-to-Peer Verification Scope
  scope "/api/vouch", KollectiveWeb do
    # Requires standard JWT validation token headers
    pipe_through [:api, :api_authenticated]

    # 1. Unverified user endpoints requesting rotating temporary token data
    post "/generate-token", VouchController, :request_token

    # 2. Verified user endpoints posting scanned text signatures
    post "/verify-peer", VouchController, :execute_peer_vouch
  end

  # lib/kollective_web/router.ex
  scope "/api/v1", KollectiveWeb do
    pipe_through [:api, :api_authenticated]

    # 1. Get a "upload ticket" for R2
    post "/media", MediaController, :create
    put "/media/:id", MediaController, :update
    get "/media/:id", MediaController, :show

    # 2. Finalize the message with the encrypted file metadata
    resources "/conversations/:conversation_id/messages", MessageController, only: [:create]
  end

  scope "/api/v1", KollectiveWeb do
    pipe_through [:api, :api_authenticated]

    # ─── REAL-TIME USER NOTIFICATION ENGINE ───
    get "/notifications", NotificationController, :index
    get "/notifications/unread_count", NotificationController, :unread_count
    post "/notifications/mark_as_read", NotificationController, :mark_as_read
  end

  scope "/api", KollectiveWeb do
    # Ensure your auth plug runs here
    pipe_through [:api, :api_authenticated]

    # 📥 Inbox List: Fetch the user's active DM list / sidebar conversations
    get "/conversations", ConversationController, :index

    # 📁 Message History: Pull older historical texts for a specific conversation thread
    get "/conversations/:conversation_id/messages", MessageController, :index

    # ✉️ Create Message: Your existing endpoint route
    post "/conversations/:conversation_id/messages", MessageController, :create
  end

  scope "/api/v1", KollectiveWeb do
    pipe_through [:api, :api_authenticated]

    post "/campaigns/apply/vouch", CandidacyAuthController, :cast_vouch
    post "/campaigns/apply/approve", CandidacyAuthController, :approve_application
    # POST /api/v1/campaigns/pitches
    # JSON Payload Body fields: %{"candidate" => %{"office_level" => "municipal", ...}, "video" => %{}}
    # 🗳️ Handles all candidate registration video posts (Municipal, County, Federal)
    post "/campaigns/declare", CampaignController, :declare_pitch

    # GET /api/v1/campaigns/pitches?level=municipal&code=austin_tx&stage=booth
    get "/campaigns/pitches", CampaignController, :index_pitches

    # POST /api/v1/campaigns/pitches/:id/vote
    # JSON Payload Body fields: %{"delta" => 1}  OR  %{"delta" => -1}
    post "/campaigns/pitches/:id/vote", CampaignController, :vote_pitch
  end

  # lib/kollective_web/router.ex
  scope "/api/v1", KollectiveWeb do
    pipe_through [:api, :api_authenticated]

    # 🗳️ Debate Logistics & Town Hall Operations
    get "/campaigns/debates", DebateController, :index_debates
    post "/campaigns/debates/shifts/:id/claim", DebateController, :claim_shift
  end

  # lib/kollective_web/router.ex
  scope "/api/v1", KollectiveWeb do
    pipe_through [:api, :api_authenticated]

    # ⏱️ Crowdsourced Civic Ledgers & Municipal Ballots Deadlines
    get "/campaigns/deadlines", DeadlineController, :index_deadlines
    post "/campaigns/deadlines", DeadlineController, :create_deadline
  end

  scope "/api", KollectiveWeb do
    # Use your application's auth plug
    pipe_through [:api, :api_authenticated]

    post "/civic/update_precinct_node", CivicController, :update_precinct_node
  end

  scope "/api/cities", KollectiveWeb do
    pipe_through [:api]

    get "/search", CityController, :search
  end

  # ─── LOCATION RESOLUTION (GEOGRAPHY ROUTE) ───
  # Public facing endpoint (no authentication required) to find offices via address/coordinates/PIN
  scope "/api/v1", KollectiveWeb do
    pipe_through :api

    post "/resolve-offices", LocationController, :resolve_offices
  end

  # District Auto-Suggest
  # Summary of Workflow:

  #  User types address on Profile page.
  #  Frontend calls GET /api/districts/lookup.
  #  Backend queries Google Civic API, parses OCD IDs, and returns JSON.
  #  User clicks "Save Districts."
  #  User Feed is now perfectly filtered for their local ballot.
  scope "/api", KollectiveWeb do
    pipe_through [:api, :api_authenticated]

    get "/districts/lookup", DistrictController, :lookup

    post "/classifieds", ClassifiedController, :create
    delete "/classifieds/:id", ClassifiedController, :delete
  end

  scope "/api", KollectiveWeb do
    pipe_through [:api]

    get "/classifieds", ClassifiedController, :index
    get "/classifieds/:id", ClassifiedController, :show
  end

  scope "/classifieds", KollectiveWeb do
    pipe_through [:api]

    get "/", ClassifiedController, :index
    get "/:id", ClassifiedController, :show
  end

  scope "/classifieds", KollectiveWeb do
    pipe_through [:api, :api_authenticated]

    post "/", ClassifiedController, :create
    delete "/:id", ClassifiedController, :delete
  end
end
