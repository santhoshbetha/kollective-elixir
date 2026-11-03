defmodule KollectiveWeb.ProposalCommentControllerTest do
  @moduledoc """
  Regression matrix for the state-geofenced Business Proposal discussion engine.

  Covers:
    * in-state residents can read and write threaded comments,
    * out-of-state residents receive a hard 403 on both reads and writes,
    * image pre-signing returns a same-origin upload ticket,
    * reply threading nests correctly under its parent.
  """
  use KollectiveWeb.ConnCase, async: true

  import Kollective.Factory
  import Ecto.Query

  alias Kollective.Repo
  alias Kollective.Businesses.ProposalComment

  setup %{conn: conn} do
    resident = insert(:user, state: "TX")
    outsider = insert(:user, state: "NY")
    proposal = insert(:business_proposal, state: "TX")

    tx_conn = authenticate_conn(conn, resident)
    ny_conn = authenticate_conn(build_conn(), outsider)

    {:ok,
     conn: conn,
     tx_conn: tx_conn,
     ny_conn: ny_conn,
     resident: resident,
     outsider: outsider,
     proposal: proposal}
  end

  describe "POST /api/v1/proposals_comments/:proposal_id/comment" do
    test "in-state resident can post a comment", %{tx_conn: conn, proposal: proposal} do
      response =
        conn
        |> post(~p"/api/v1/proposals_comments/#{proposal.id}/comment", %{
          "comment" => %{"content" => "I will back this tool library!"}
        })
        |> json_response(201)

      assert response["status"] == "success"
      assert response["data"]["content"] == "I will back this tool library!"
      assert response["data"]["moderation_status"] == "approved"
      assert response["data"]["business_id"] == to_string(proposal.id)
      assert response["data"]["author"]["username"]
    end

    test "in-state resident can post a threaded reply", %{
      tx_conn: conn,
      proposal: proposal,
      resident: resident
    } do
      parent =
        insert(:proposal_comment,
          business: proposal,
          user: resident,
          content: "Parent thread node"
        )

      response =
        conn
        |> post(~p"/api/v1/proposals_comments/#{proposal.id}/comment", %{
          "comment" => %{"content" => "Nested reply node", "parent_id" => parent.id}
        })
        |> json_response(201)

      assert response["data"]["parent_id"] == to_string(parent.id)
    end

    test "out-of-state resident is rejected with 403 and nothing is persisted", %{
      ny_conn: conn,
      proposal: proposal
    } do
      response =
        conn
        |> post(~p"/api/v1/proposals_comments/#{proposal.id}/comment", %{
          "comment" => %{"content" => "Out of state spam attempt"}
        })
        |> json_response(403)

      assert response["error"] == "Discussion locked to local state residents"

      assert Repo.aggregate(
               from(c in ProposalComment, where: c.business_id == ^proposal.id),
               :count
             ) == 0
    end

    test "returns 404 for an unknown proposal", %{tx_conn: conn} do
      response =
        conn
        |> post(~p"/api/v1/proposals_comments/#{Ecto.ULID.generate()}/comment", %{
          "comment" => %{"content" => "Ghost node"}
        })
        |> json_response(404)

      assert response["status"] == "error"
    end
  end

  describe "GET /api/v1/proposal_comments" do
    test "in-state resident lists approved top-level comments with nested replies", %{
      tx_conn: conn,
      proposal: proposal,
      resident: resident
    } do
      parent = insert(:proposal_comment, business: proposal, user: resident)
      _reply = insert(:proposal_comment, business: proposal, user: resident, parent: parent)
      _pending = insert(:proposal_comment, business: proposal, user: resident, moderation_status: "pending")

      response =
        conn
        |> get(~p"/api/v1/proposal_comments", %{"proposal_id" => proposal.id})
        |> json_response(200)

      assert response["status"] == "success"
      assert length(response["data"]) == 1

      [thread] = response["data"]
      assert thread["id"] == to_string(parent.id)
      assert length(thread["replies"]) == 1
    end

    test "out-of-state resident cannot read the discussion stream", %{
      ny_conn: conn,
      proposal: proposal,
      resident: resident
    } do
      insert(:proposal_comment, business: proposal, user: resident)

      response =
        conn
        |> get(~p"/api/v1/proposal_comments", %{"proposal_id" => proposal.id})
        |> json_response(403)

      assert response["error"] == "Discussion locked to local state residents"
    end
  end

  describe "GET /api/v1/proposal_comments/image/presign" do
    test "returns a same-origin upload proxy ticket", %{tx_conn: conn} do
      response =
        conn
        |> get(~p"/api/v1/proposal_comments/image/presign", %{"content_type" => "image/png"})
        |> json_response(200)

      assert response["status"] == "success"
      assert String.starts_with?(response["upload_url"], "/media/proposal_comments/")
      assert String.ends_with?(response["upload_url"], ".png")
      assert response["final_asset_url"]
    end
  end
end
