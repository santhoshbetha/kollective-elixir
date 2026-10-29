defmodule KollectiveWeb.OrganizationSocialMutationsTest do
  use KollectiveWeb.ConnCase, async: true
  import Kollective.Factory
  import Ecto.Query

  alias Kollective.Repo
  alias Kollective.Accounts.{Accounts, OrganizationMembership, UserRelationship}
  alias Kollective.Posts.{Like, Post}
  alias Kollective.Polls.{Poll, PollOption, PollVote}
  alias Kollective.Events.Participant

  setup do
    # Create Organization
    org =
      insert(:user,
        type: :organization,
        display_name: "Action Collective",
        username: "action_org_#{System.unique_integer([:positive])}"
      )

    # Create Org Admin User and Membership
    admin_user =
      insert(:user,
        username: "org_admin_#{System.unique_integer([:positive])}"
      )

    Repo.insert!(%OrganizationMembership{
      user_id: admin_user.id,
      organization_id: org.id,
      role: :admin,
      status: :approved
    })

    admin_token = Accounts.generate_organization_session_token(admin_user, org.id)

    # Create Org Non-Admin User (contributor) and Membership
    non_admin_user =
      insert(:user,
        username: "org_contributor_#{System.unique_integer([:positive])}"
      )

    Repo.insert!(%OrganizationMembership{
      user_id: non_admin_user.id,
      organization_id: org.id,
      role: :contributor,
      status: :approved
    })

    non_admin_token = Accounts.generate_organization_session_token(non_admin_user, org.id)

    # Helper closures for building authenticated connections
    build_org_conn = fn raw_token ->
      ip_part1 = rem(System.unique_integer([:positive]), 250) + 1
      ip_part2 = :rand.uniform(250)
      ip_part3 = :rand.uniform(250)

      Phoenix.ConnTest.build_conn()
      |> Map.put(:remote_ip, {10, ip_part1, ip_part2, ip_part3})
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{raw_token}")
    end

    %{
      org: org,
      admin_user: admin_user,
      admin_token: admin_token,
      admin_conn: build_org_conn.(admin_token),
      non_admin_user: non_admin_user,
      non_admin_token: non_admin_token,
      non_admin_conn: build_org_conn.(non_admin_token)
    }
  end

  describe "Follow Mutations Under Organization Context" do
    test "non-admin token is rejected with 403 Forbidden and leaves relationships unmodified", %{
      non_admin_conn: conn,
      org: org
    } do
      target_user = insert(:user)

      res =
        conn
        |> post(~p"/api/v1/relationships/toggle", %{
          "target_id" => target_user.id,
          "type" => "follow"
        })
        |> json_response(403)

      assert res["error"] == "forbidden"
      assert res["message"] =~ "Only administrators can perform social actions"

      # Verify 0 database records were created for this organization
      assert Repo.all(from(r in UserRelationship, where: r.source_id == ^org.id)) == []
    end

    test "admin token successfully creates relationship attributed to the organization", %{
      admin_conn: conn,
      org: org
    } do
      target_user = insert(:user)

      res =
        conn
        |> post(~p"/api/v1/relationships/toggle", %{
          "target_id" => target_user.id,
          "type" => "follow"
        })
        |> json_response(200)

      assert res["status"] == "success"

      # Verify relationship is attributed directly to org.id
      rel = Repo.one(from(r in UserRelationship, where: r.source_id == ^org.id and r.target_id == ^target_user.id))
      assert rel != nil
      assert rel.type == "follow"
    end
  end

  describe "Like Mutations Under Organization Context" do
    test "non-admin token is rejected with 403 Forbidden and leaves likes unmodified", %{
      non_admin_conn: conn,
      org: org
    } do
      post_item = insert(:post)

      res =
        conn
        |> post(~p"/api/v1/posts/#{post_item.id}/like")
        |> json_response(403)

      assert res["error"] == "forbidden"
      assert res["message"] =~ "Only administrators can perform social actions"

      # Verify 0 like records exist for this organization
      assert Repo.all(from(l in Like, where: l.user_id == ^org.id)) == []
    end

    test "admin token successfully creates like attributed to the organization", %{
      admin_conn: conn,
      org: org
    } do
      post_item = insert(:post)

      res =
        conn
        |> post(~p"/api/v1/posts/#{post_item.id}/like")
        |> json_response(200)

      assert res["status"] == "success"

      # Verify like is attributed directly to org.id
      like = Repo.one(from(l in Like, where: l.user_id == ^org.id and l.post_id == ^post_item.id))
      assert like != nil
    end
  end

  describe "Reblog Mutations Under Organization Context" do
    test "non-admin token is rejected with 403 Forbidden and leaves posts unmodified", %{
      non_admin_conn: conn,
      org: org
    } do
      post_item = insert(:post)

      res =
        conn
        |> post(~p"/api/v1/posts/#{post_item.id}/reblog")
        |> json_response(403)

      assert res["error"] == "forbidden"
      assert res["message"] =~ "Only administrators can perform social actions"

      # Verify 0 reblog records exist for this organization
      assert Repo.all(from(p in Post, where: p.organization_id == ^org.id)) == []
    end

    test "admin token successfully creates reblog attributed to the organization", %{
      admin_conn: conn,
      org: org
    } do
      post_item = insert(:post)

      res =
        conn
        |> post(~p"/api/v1/posts/#{post_item.id}/reblog")
        |> json_response(201)

      assert res["status"] == "success"

      # Verify reblog post is attributed to organization_id
      reblog_post =
        Repo.one(from(p in Post, where: p.organization_id == ^org.id and p.reblog_of_id == ^post_item.id))

      assert reblog_post != nil
    end
  end

  describe "Poll Vote Mutations Under Organization Context" do
    test "non-admin token is rejected with 403 Forbidden and leaves poll_votes unmodified", %{
      non_admin_conn: conn,
      org: org
    } do
      author = insert(:user)
      post_item = insert(:post, author: author, visibility: "public", status: :published)

      poll =
        Repo.insert!(%Poll{
          post_id: post_item.id,
          expires_at:
            DateTime.utc_now() |> DateTime.add(86400, :second) |> DateTime.truncate(:second),
          votes_count: 0
        })

      _opt1 =
        Repo.insert!(%PollOption{
          poll_id: poll.id,
          title: "Option A",
          votes_count: 0
        })

      res =
        conn
        |> post(~p"/api/v1/polls/#{poll.id}/votes", %{"choices" => [0]})
        |> json_response(403)

      assert res["error"] == "forbidden"
      assert res["message"] =~ "Only administrators can perform social actions"

      # Verify 0 poll votes exist for this organization
      assert Repo.all(from(v in PollVote, where: v.user_id == ^org.id)) == []
    end

    test "admin token successfully votes attributed to the organization", %{
      admin_conn: conn,
      org: org
    } do
      author = insert(:user)
      post_item = insert(:post, author: author, visibility: "public", status: :published)

      poll =
        Repo.insert!(%Poll{
          post_id: post_item.id,
          expires_at:
            DateTime.utc_now() |> DateTime.add(86400, :second) |> DateTime.truncate(:second),
          votes_count: 0
        })

      opt1 =
        Repo.insert!(%PollOption{
          poll_id: poll.id,
          title: "Option A",
          votes_count: 0
        })

      res =
        conn
        |> post(~p"/api/v1/polls/#{poll.id}/votes", %{"choices" => [0]})
        |> json_response(200)

      assert res["status"] == "success"

      # Verify poll vote is attributed directly to org.id
      vote = Repo.one(from(v in PollVote, where: v.user_id == ^org.id and v.poll_id == ^poll.id))
      assert vote != nil
      assert vote.option_id == opt1.id
    end
  end

  describe "Event RSVP Mutations Under Organization Context" do
    test "non-admin token is rejected with 403 Forbidden and leaves event_participants unmodified", %{
      non_admin_conn: conn,
      org: org
    } do
      organizer = insert(:user)

      event =
        insert(:event,
          created_by: organizer.id,
          user: organizer,
          organization: organizer,
          join_mode: "free",
          title: "Grassroots Assembly"
        )

      res =
        conn
        |> post(~p"/api/v1/kollective/events/#{event.id}/rsvp", %{"status" => "attending"})
        |> json_response(403)

      assert res["error"] == "forbidden"
      assert res["message"] =~ "Only administrators can perform social actions"

      # Verify 0 event participants exist for this organization
      assert Repo.all(from(p in Participant, where: p.user_id == ^org.id)) == []
    end

    test "admin token successfully RSVPs to event attributed to the organization", %{
      admin_conn: conn,
      org: org
    } do
      organizer = insert(:user)

      event =
        insert(:event,
          created_by: organizer.id,
          user: organizer,
          organization: organizer,
          join_mode: "free",
          title: "Grassroots Assembly"
        )

      res =
        conn
        |> post(~p"/api/v1/kollective/events/#{event.id}/rsvp", %{"status" => "attending"})
        |> json_response(200)

      assert res["status"] == "success"

      # Verify participant row is attributed directly to org.id
      part = Repo.one(from(p in Participant, where: p.user_id == ^org.id and p.event_id == ^event.id))
      assert part != nil
      assert part.status == "accepted"
    end

    test "non-admin token is rejected with 403 on Action RSVP and admin succeeds", %{
      non_admin_conn: non_admin_conn,
      admin_conn: admin_conn,
      org: org
    } do
      organizer = insert(:user)

      action =
        insert(:event,
          created_by: organizer.id,
          user: organizer,
          organization: organizer,
          join_mode: "free",
          title: "Community Action Rally"
        )

      # 1. Non-admin is rejected with 403
      res_non_admin =
        non_admin_conn
        |> post(~p"/api/v1/actions/#{action.id}/rsvp", %{"status" => "attending"})
        |> json_response(403)

      assert res_non_admin["error"] == "forbidden"
      assert res_non_admin["message"] =~ "Only administrators can perform social actions"
      assert Repo.all(from(p in Participant, where: p.user_id == ^org.id)) == []

      # 2. Admin succeeds with 200
      res_admin =
        admin_conn
        |> post(~p"/api/v1/actions/#{action.id}/rsvp", %{"status" => "attending"})
        |> json_response(200)

      assert res_admin["status"] == "success"
      part = Repo.one(from(p in Participant, where: p.user_id == ^org.id and p.event_id == ^action.id))
      assert part != nil
      assert part.status == "accepted"
    end
  end
end
