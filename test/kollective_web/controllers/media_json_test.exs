# test/kollective_web/controllers/media_json_test.exs
defmodule KollectiveWeb.MediaJSONTest do
  use KollectiveWeb.ConnCase, async: true

  alias Kollective.Posts.PostAttachment
  alias KollectiveWeb.MediaJSON

  describe "MediaJSON serialization" do
    test "presign/1 formats direct-to-cloud upload ticket" do
      result =
        MediaJSON.presign(%{
          upload_url: "https://r2.dev/upload?ticket=xyz",
          final_asset_url: "https://r2.dev/attachments/media_123.jpg"
        })

      assert result.status == "success"
      assert result.upload_url == "https://r2.dev/upload?ticket=xyz"
      assert result.final_asset_url == "https://r2.dev/attachments/media_123.jpg"
    end

    test "data/1 serializes image and video attachment types accurately" do
      image_att = %PostAttachment{
        id: "01HXYZATT00000000000000001",
        url: "https://r2.dev/pic.png",
        media_type: "image/png",
        description: "A sunset photo",
        blurhash: "L6PZfsi_00Kj"
      }

      image_data = MediaJSON.data(image_att)
      assert image_data.id == "01HXYZATT00000000000000001"
      assert image_data.type == "image"
      assert image_data.description == "A sunset photo"
      assert image_data.url == "https://r2.dev/pic.png"

      video_att = %PostAttachment{
        id: "01HXYZATT00000000000000002",
        url: "https://r2.dev/clip.mp4",
        media_type: "video/mp4",
        description: "A short clip",
        blurhash: nil
      }

      video_data = MediaJSON.data(video_att)
      assert video_data.type == "video"
    end

    test "show/1 and index/1 format single and collection responses" do
      att = %PostAttachment{
        id: "01HXYZATT00000000000000003",
        url: "https://r2.dev/doc.jpg",
        media_type: "image/jpeg",
        description: "",
        blurhash: ""
      }

      show_result = MediaJSON.show(%{media: att})
      assert show_result.status == "success"
      assert show_result.data.id == "01HXYZATT00000000000000003"

      index_result = MediaJSON.index([att])
      assert length(index_result) == 1
      assert hd(index_result).id == "01HXYZATT00000000000000003"
    end
  end
end
