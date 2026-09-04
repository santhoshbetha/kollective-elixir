# 1. Force your application supervisor tree (and Kollective.Repo) to start first
{:ok, _} = Application.ensure_all_started(:kollective)

# 2. Initialize the test framework execution tracker
ExUnit.start()

# 3. Safely switch your active, running repository pool over to manual Sandbox mode
Ecto.Adapters.SQL.Sandbox.mode(Kollective.Repo, :manual)

Mox.defmock(Kollective.EventsMock, for: [])

# 🚀 FIX: Force the compiler to load the behavior module before creating the mock
Code.ensure_compiled!(Kollective.HTTPClient)
Mox.defmock(Kollective.HTTPClientMock, for: Kollective.HTTPClient)

# Instruct Mox to auto-generate the ServiceMock module using the Behaviour contract
Code.ensure_compiled!(Kollective.Geospatial.Behaviour)
Mox.defmock(Kollective.Geospatial.ServiceMock, for: Kollective.Geospatial.Behaviour)

Mox.defmock(Kollective.SecurityMock, for: [])
Mox.defmock(Kollective.ModerationMock, for: [])
Mox.defmock(Kollective.AccountsMock, for: [])
Mox.defmock(Kollective.EmailMock, for: [])
Mox.defmock(Kollective.MediaUploaderMock, for: [])
Mox.defmock(Kollective.PushNotifierMock, for: [])
