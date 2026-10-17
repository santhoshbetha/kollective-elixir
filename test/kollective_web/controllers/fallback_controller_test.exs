defmodule KollectiveWeb.FallbackControllerTest do
  use KollectiveWeb.ConnCase, async: true

  alias KollectiveWeb.FallbackController

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")

    {:ok, conn: conn}
  end

  describe "FallbackController.call/2" do
    test "handles changeset errors with 422 unprocessable_entity", %{conn: conn} do
      changeset =
        {%{}, %{email: :string}}
        |> Ecto.Changeset.cast(%{}, [:email])
        |> Ecto.Changeset.validate_required([:email])

      conn = FallbackController.call(conn, {:error, changeset})
      res = json_response(conn, 422)

      assert res["errors"]["email"] != nil
    end

    test "handles :not_authorized with 403 forbidden", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :not_authorized})
      res = json_response(conn, 403)

      assert res["status"] == "error"
      assert res["code"] == "UNAUTHORIZED_ACTION"
      assert res["message"] =~ "clearance tiers"
    end

    test "handles :token_expired with 410 gone", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :token_expired})
      res = json_response(conn, 410)

      assert res["status"] == "error"
      assert res["code"] == "APPLICATION_EXPIRED"
      assert res["message"] =~ "single-use token"
    end

    test "handles :token_invalid with 400 bad_request", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :token_invalid})
      res = json_response(conn, 400)

      assert res["status"] == "error"
      assert res["code"] == "INVALID_TOKEN_SIGNATURE"
    end

    test "handles :already_voted with 409 conflict", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :already_voted})
      res = json_response(conn, 409)

      assert res["status"] == "error"
      assert res["code"] == "DUPLICATE_BALLOT"
    end

    test "handles :invalid_orcid_record with 400 bad_request", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :invalid_orcid_record})
      res = json_response(conn, 400)

      assert res["status"] == "error"
      assert res["code"] == "ORCID_RECORD_MISSING"
    end

    test "handles binary string reasons with 422 unprocessable_entity", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, "Transaction rollback triggered"})
      res = json_response(conn, 422)

      assert res["status"] == "error"
      assert res["code"] == "PIPELINE_TRANSACTION_REJECTED"
      assert res["message"] == "Transaction rollback triggered"
    end
  end
end
