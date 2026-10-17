defmodule KollectiveWeb.Admin.SovereignControllerTest do
  use ExUnit.Case, async: true

  test "SovereignController is deprecated and documents replacements" do
    {:docs_v1, _annotation, :elixir, _format, %{"en" => doc}, _metadata, _docs} =
      Code.fetch_docs(KollectiveWeb.Admin.SovereignController)

    assert doc =~ "DEPRECATED"
    assert doc =~ "MeshIncidentController"
    assert doc =~ "SovereignOperatorController"
  end
end
