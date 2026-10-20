defmodule KollectiveWeb.OptionsControllerTest do
  use KollectiveWeb.ConnCase, async: true

  describe "OPTIONS /*path" do
    test "returns 204 No Content for CORS preflight options requests", %{conn: conn} do
      conn =
        recycle(conn)
        |> Phoenix.ConnTest.dispatch(KollectiveWeb.Endpoint, :options, "/api/v1/any/path")

      assert response(conn, 204) == ""
    end
  end
end
