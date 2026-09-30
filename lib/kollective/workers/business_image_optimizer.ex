defmodule Kollective.Workers.BusinessImageOptimizer do
  use Oban.Worker, queue: :media, max_attempts: 3

  alias Kollective.Repo
  # Adjust namespace to match your local structure
  alias Kollective.Businesses.Business

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"business_id" => id}}) do
    business = Repo.get!(Business, id)

    case business.profile_image_url do
      nil ->
        :ok

      "" ->
        :ok

      input_url ->
        optimized_path = "/tmp/optimized_business_#{id}.jpg"

        try do
          # 1️⃣ Stream down raw frontend image payload bytes into temp server disk cache
          with {:ok, %{status: 200, body: raw_bytes}} <- Req.get(input_url),
               :ok <- File.write(optimized_path, raw_bytes),

               # 2️⃣ Run graphics-accelerated image conversion matrix via ImageMagick
               :ok <- compress_business_profile_image(optimized_path),

               # 3️⃣ Upload the web-ready asset container payload to your R2 bucket via Waffle
               {:ok, processed_filename} <-
                 Kollective.Media.BusinessImage.store(
                   {%{path: optimized_path, filename: "profile.jpg"}, business}
                 ) do
            # Resolve absolute secure public CDN link destination string
            final_cdn_url =
              Kollective.Media.BusinessImage.url({processed_filename, business}, :original)

            # 4️⃣ Update the business profile row column directly inside the repo
            business
            |> Ecto.Changeset.change(%{
              profile_image_url: final_cdn_url,
              is_image_processed: true
            })
            |> Repo.update()

            :ok
          else
            error -> {:error, "Business asset optimization step exception: #{inspect(error)}"}
          end
        after
          # 🧹 Server Disk Shield: Always erase temporary files immediately
          File.rm(optimized_path)
        end
    end
  end

  defp compress_business_profile_image(path) do
    try do
      import Mogrify

      open(path)
      # Constrain profile images to standard resolution bounds
      |> resize_to_limit("800x800>")
      # Force high-fidelity progressive compression layout
      |> custom("interlace", "plane")
      # Strip EXIF meta tags strings
      |> custom("strip")
      # Crisp definition balance quality factor threshold
      |> quality(85)
      |> save(in_place: true)

      :ok
    rescue
      err -> {:error, err}
    end
  end
end
