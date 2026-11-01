defmodule Kollective.MediaProcessorTest do
  use ExUnit.Case, async: true

  alias Kollective.Media.MediaProcessor

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "media_processor_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  test "process_upload/2 executes using Image library, strips metadata, and limits resolution to max 2048px", %{tmp_dir: tmp_dir} do
    # Create a test PNG binary with 4000x3000 resolution and metadata
    large_w = 4000
    large_h = 3000
    # Valid minimal PNG header for 4000x3000
    png_binary = <<
      137, 80, 78, 71, 13, 10, 26, 10,
      0, 0, 0, 13,
      "IHDR",
      large_w::32,
      large_h::32,
      8, 2, 0, 0, 0,
      0, 0, 0, 0
    >>

    upload_path = Path.join(tmp_dir, "large_input.png")
    target_dest = Path.join(tmp_dir, "processed_output.png")
    File.write!(upload_path, png_binary)

    # 1. Execute upload processing
    assert {:ok, dest} = MediaProcessor.process_upload(upload_path, target_dest)
    assert dest == target_dest
    assert File.exists?(target_dest)

    # 2. Verify bounding resolution is constrained to a maximum of 2048px
    assert {:ok, img} = Image.open(upload_path)
    assert {:ok, optimized} = Image.minimize_metadata(img)
    assert {:ok, thumbnail} = Image.thumbnail(optimized, 2048)

    assert Image.width(thumbnail) <= 2048
    assert Image.height(thumbnail) <= 2048

    # 3. Verify metadata was minimized / stripped
    assert {:ok, meta} = Image.metadata(thumbnail)
    assert meta == %{}

    # 4. Verify delegate module Kollective.MediaProcessor also works
    delegate_dest = Path.join(tmp_dir, "delegate_output.png")
    assert {:ok, _} = Kollective.MediaProcessor.process_upload(upload_path, delegate_dest)
    assert File.exists?(delegate_dest)
  end

  test "process_upload/2 preserves bounding resolution for images already under 2048px", %{tmp_dir: tmp_dir} do
    small_w = 1200
    small_h = 800
    png_binary = <<
      137, 80, 78, 71, 13, 10, 26, 10,
      0, 0, 0, 13,
      "IHDR",
      small_w::32,
      small_h::32,
      8, 2, 0, 0, 0,
      0, 0, 0, 0
    >>

    upload_path = Path.join(tmp_dir, "small_input.png")
    target_dest = Path.join(tmp_dir, "small_output.png")
    File.write!(upload_path, png_binary)

    assert {:ok, _} = MediaProcessor.process_upload(upload_path, target_dest)

    assert {:ok, img} = Image.open(upload_path)
    assert {:ok, thumb} = Image.thumbnail(img, 2048)
    assert Image.width(thumb) == 1200
    assert Image.height(thumb) == 800
  end
end

