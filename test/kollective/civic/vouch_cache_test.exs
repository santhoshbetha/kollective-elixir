defmodule Kollective.Civic.VouchCacheTest do
  use Kollective.DataCase, async: true
  import Kollective.Factory
  alias Kollective.Civic.VouchCache
  alias Kollective.Civic.TokenSchema

  test "consumes token via fast path and purges the backing database row synchronously" do
    user = insert(:user)
    token = VouchCache.generate_token(user.id)

    # Verify token row exists initially
    assert Kollective.Repo.get_by(TokenSchema, token: token)

    # Consume the token (Hits Cachex fast path)
    assert {:ok, fetched_user_id} = VouchCache.consume_token(token)
    assert fetched_user_id == user.id

    # 🚀 Because it ran inline, we can assert right away without Flaky Sleep timers!
    refute Kollective.Repo.get_by(TokenSchema, token: token)
  end
end
