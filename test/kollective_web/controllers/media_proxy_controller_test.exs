defmodule KollectiveWeb.MediaProxyControllerTest do
  use KollectiveWeb.ConnCase, async: false

  test "PUT /media/*path uploads binary and GET /media/*path serves it", %{conn: conn} do
    png_data = <<137, 80, 78, 71, 13, 10, 26, 10>>
    path = "kollective-test/attachments/test-user/sample.png"

    upload_conn =
      conn
      |> put_req_header("content-type", "image/png")
      |> put("/media/#{path}", png_data)

    assert json_response(upload_conn, 200)["status"] == "ok"

    serve_conn = get(conn, "/media/#{path}")
    assert serve_conn.status == 200
    assert serve_conn.resp_body == png_data
    assert response_content_type(serve_conn, :png) =~ "image/png"
  end

  test "GET /media/*path returns 404 when file does not exist", %{conn: conn} do
    conn = get(conn, "/media/non_existent_image_12345.png")
    assert json_response(conn, 404)["error"] == "Media not found"
  end

  test "sanitizes directory traversal in keys", %{conn: conn} do
    png_data = <<137, 80, 78, 71, 13, 10, 26, 10>>
    upload_conn =
      conn
      |> put_req_header("content-type", "image/png")
      |> put("/media/../../traversal.png", png_data)
    assert json_response(upload_conn, 200)["status"] == "ok"

    serve_conn = get(conn, "/media/traversal.png")
    assert serve_conn.status == 200
    assert serve_conn.resp_body == png_data
  end
end
