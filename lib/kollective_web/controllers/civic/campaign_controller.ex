# lib/kollective_web/controllers/api/v1/campaign_controller.ex
defmodule KollectiveWeb.CampaignController do
  use KollectiveWeb, :controller

  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Videos.CandidateVideo
  alias Kollective.Videos.Uploader
  alias Kollective.Accounts.User

  action_fallback KollectiveWeb.FallbackController

  @doc """
  Processes multi-part incoming requests to declare a candidacy pitch.
  Determines the routing flow path automatically based on target office level selection parameters.
  """
  def declare_pitch(conn, %{"candidate" => pitch_params, "video" => video_plug}) do
    # 1. Extract the current user session context token signatures
    user_id = conn.assigns[:current_user_id] || (conn.assigns[:current_user] && conn.assigns[:current_user].id)
    user = Repo.get!(User, user_id)

    # 2. Strict Ingress Guard: Verify this profile is authorized to register as a candidate
    if user.is_candidate do
      # 3. Offload the heavy binary video multipart chunks straight to object storage
      case Uploader.upload_video(video_plug) do
        {:ok, stored_media_url} ->
          # 4. Extract office type to determine routing path
          office_level = Map.get(pitch_params, "office_level", "congress")

          # 🎯 THE DUAL-FLOW ROUTING ASSIGNER MATRIX
          flow_attrs =
            if office_level in ["municipal", "county"] do
              # 🏙️ B. LOCAL POSITIONS FLOW: Bind parameters straight to micro-precinct neighborhood block indices
              pitch_params
              # Capture the candidate's exact home location variables automatically to isolate their registry
              |> Map.put("polling_booth_id", user.polling_booth_id)
              |> Map.put("sub_district", user.sub_district)
              # Ingress step for local flows
              # Set the initial pre-filter stage so general city populations aren't overwhelmed by the upload
              |> Map.put("visibility_stage", "booth")
            else
              # 🏛️ A. HIGH POSITIONS FLOW: Bind parameters straight to vertical regional escalation tiers
              pitch_params
              # Ingress step for high flows
              |> Map.put("visibility_stage", "booth_primary")
            end

          full_attrs =
            flow_attrs
            |> Map.put("video_url", stored_media_url)
            |> Map.put("user_id", user_id)

          %CandidateVideo{}
          |> CandidateVideo.changeset(full_attrs)
          |> Repo.insert()
          |> case do
            {:ok, saved_video} ->
              conn
              # 💾 Record success at the precise ingress point (Neighborhood Block or Primary Stage)
              |> put_status(:created)
              # 🔌 Return the full video object to trigger the React frontend redirect to the Candidate Dashboard
              |> json(Repo.preload(saved_video, :user))

            {:error, changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)})
          end

        {:error, _reason} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Media ingestion pipeline storage write failure."})
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Account profile lacks candidate validation credentials."})
    end
  end

  @doc """
  Streams a ranked list of pitches filtered explicitly down to current pipeline stage parameters.
  Supports both High Position escalations and Local Position micro-precinct filters.
  GET /api/v1/campaigns/pitches?level=municipal&code=austin_tx&stage=booth
  """
  def index_pitches(conn, %{"level" => office_level, "code" => district_code, "stage" => stage}) do
    query =
      case {office_level, stage} do
        # 🏙️ FLOW B: LOCAL POSITION DIRECTORY SLICES
        {"municipal", "booth"} ->
          from v in CandidateVideo,
            where: v.office_level == "municipal" and v.polling_booth_id == ^district_code,
            order_by: [desc: v.votes_count]

        {"municipal", "ward"} ->
          from v in CandidateVideo,
            where: v.office_level == "municipal" and v.sub_district == ^district_code,
            order_by: [desc: v.votes_count],
            limit: 15

        {"municipal", "public"} ->
          from v in CandidateVideo,
            where: v.office_level == "municipal" and v.district_code == ^district_code,
            order_by: [desc: v.votes_count],
            limit: 10

        # 🏛️ FLOW A: HIGH POSITION REGIONAL SLICES
        {_, "booth_primary"} ->
          from v in CandidateVideo,
            where: v.office_level == ^office_level and v.polling_booth_id == ^district_code,
            order_by: [desc: v.votes_count]

        {_, "sub_district_primary"} ->
          from v in CandidateVideo,
            where: v.office_level == ^office_level and v.sub_district == ^district_code,
            order_by: [desc: v.votes_count],
            limit: 5

        {_, "public_slate"} ->
          from v in CandidateVideo,
            where: v.office_level == ^office_level and v.district_code == ^district_code,
            order_by: [desc: v.votes_count],
            limit: 5
      end

    pitches = Repo.all(query) |> Repo.preload(:user)
    json(conn, pitches)
  end

  # lib/kollective_web/controllers/api/v1/campaign_controller.ex

  def index_pitche2(conn, %{"level" => "municipal", "code" => district_code, "stage" => stage}) do
    # import Ecto.Query
    # alias Kollective.Videos.CandidateVideo

    # 🔬 AUTOMATED INGRES FILTERING MATRIX
    query =
      case stage do
        "booth" ->
          # Show ONLY candidates uploaded within the voter's exact neighborhood block
          from v in CandidateVideo,
            where: v.office_level == "municipal" and v.polling_booth_id == ^district_code,
            order_by: [desc: v.votes_count]

        "ward" ->
          # Show top candidates within the voter's local sub-district zone
          from v in CandidateVideo,
            where: v.office_level == "municipal" and v.sub_district == ^district_code,
            order_by: [desc: v.votes_count],
            # Restricts information overload automatically
            limit: 15

        "public" ->
          # The main city dashboard view: returns the vetted final slate
          from v in CandidateVideo,
            where: v.office_level == "municipal" and v.district_code == ^district_code,
            order_by: [desc: v.votes_count],
            limit: 10
      end

    pitches = Repo.all(query) |> Repo.preload(:user)
    json(conn, pitches)
  end

  @doc """
  Executes thread-safe, atomic upvote and downvote increments for video pitches.
  Protects against concurrent vote collision race conditions using database-level updates.
  """
  def vote_pitch(conn, %{"id" => video_id, "delta" => delta}) when delta in [1, -1] do
    # import Ecto.Query
    # alias Kollective.Videos.CandidateVideo

    # 1. Target the distinct video pitch tracking primary key row
    query = from v in CandidateVideo, where: v.id == ^video_id

    # 2. ⚡ ATOMIC DB UPDATE: Instruct PostgreSQL to shift the integer on disk immediately
    # This prevents race conditions under high concurrent constituent participation traffic.
    case Repo.update_all(query, inc: [votes_count: delta]) do
      {1, _} ->
        # 3. Fetch the fresh, updated object mapping along with user relationships to return to the UI
        updated_video =
          CandidateVideo
          |> Repo.get!(video_id)
          |> Repo.preload(:user)

        conn
        |> put_status(:ok)
        |> json(updated_video)

      {0, _} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Target pitch media parameters unresolved or unindexed."})
    end
  end

  # Fallback catch route guard to intercept malicious payload mutation score modifications (e.g. delta: 500)
  # lib/kollective_web/controllers/api/v1/campaign_controller.ex

  @doc """
  Locks voting parameters to one entry per account profile.
  Executes an inside transaction to insert the ledger row and update counts securely.
  """
  def vote_pitch2(conn, %{"id" => video_id}) do
    user_id = conn.assigns.current_user_id
    # alias Kollective.Repo
    # alias Kollective.Videos.CandidateVideo

    # Execute transactions sequentially inside an atomic SQL operation box
    Repo.transaction(fn ->
      # 1. Attempt to insert the unique vote tracking ledger row
      # If this pair already exists, PostgreSQL rejects the entry natively
      case Repo.query(
             "INSERT INTO pitch_votes (user_id, candidate_video_id, inserted_at, updated_at) VALUES ($1, $2, NOW(), $3) ON CONFLICT DO NOTHING",
             [user_id, video_id, user_id]
           ) do
        {:ok, %{num_rows: 1}} ->
          # 2. Increment total score counters atomically inside your core schema tables
          query = from v in CandidateVideo, where: v.id == ^video_id
          Repo.update_all(query, inc: [votes_count: 1])

          # 3. Return the freshly updated map payload back to the client UI layout views
          CandidateVideo |> Repo.get!(video_id) |> Repo.preload(:user)

        _ ->
          # If no rows were inserted, it means this account profile has already voted for this video
          Repo.rollback(:duplicate_vote_detected)
      end
    end)
    |> case do
      {:ok, updated_video} ->
        conn |> put_status(:ok) |> json(updated_video)

      {:error, :duplicate_vote_detected} ->
        conn
        |> put_status(:conflict)
        |> json(%{
          error: "You have already cast your endorsement signature for this candidate pitch."
        })
    end
  end
end
