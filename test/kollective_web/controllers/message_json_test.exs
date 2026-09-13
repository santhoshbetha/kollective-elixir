defmodule KollectiveWeb.MessageJSONTest do
  use KollectiveWeb.ConnCase, async: true

  alias Kollective.Chats.Message
  alias KollectiveWeb.MessageJSON

  describe "MessageJSON serialization" do
    setup do
      msg = %Message{
        id: "01HXYZMESSAGE0000000000000",
        conversation_id: "01HXYZCONV0000000000000000",
        sender_id: 42,
        encrypted_content: "Encrypted payload",
        file_url: "https://storage.com/file.png",
        file_name: "file.png",
        file_iv: "base64iv",
        encrypted_file_key: "base64key",
        inserted_at: ~U[2026-02-01 12:00:00Z],
        updated_at: ~U[2026-02-01 12:00:00Z]
      }

      {:ok, msg: msg}
    end

    test "data/1 serializes message struct", %{msg: msg} do
      data = MessageJSON.data(msg)

      assert data.id == "01HXYZMESSAGE0000000000000"
      assert data.conversation_id == "01HXYZCONV0000000000000000"
      assert data.sender_id == 42
      assert data.encrypted_content == "Encrypted payload"
      assert data.file_url == "https://storage.com/file.png"
    end

    test "data/1 serializes map", %{msg: msg} do
      map = Map.from_struct(msg)
      data = MessageJSON.data(map)

      assert data.id == "01HXYZMESSAGE0000000000000"
      assert data.encrypted_content == "Encrypted payload"
    end

    test "show/1 wraps data in map", %{msg: msg} do
      rendered = MessageJSON.show(%{message: msg})

      assert rendered.data.id == "01HXYZMESSAGE0000000000000"
    end

    test "index/1 without cursor serializes list of messages", %{msg: msg} do
      rendered = MessageJSON.index(%{messages: [msg]})

      assert length(rendered.data) == 1
      assert hd(rendered.data).id == "01HXYZMESSAGE0000000000000"
    end

    test "index/1 with next_cursor includes pagination", %{msg: msg} do
      rendered = MessageJSON.index(%{messages: [msg], next_cursor: "01HXYZMESSAGE0000000000000"})

      assert length(rendered.data) == 1
      assert rendered.pagination.next_cursor == "01HXYZMESSAGE0000000000000"
    end

    test "broadcast_data/1 serializes message for WebSocket delivery", %{msg: msg} do
      payload = MessageJSON.broadcast_data(msg)

      assert payload.id == "01HXYZMESSAGE0000000000000"
      assert payload.sender_id == 42
      assert payload.encrypted_content == "Encrypted payload"
      assert payload.file_url == "https://storage.com/file.png"
    end
  end
end
