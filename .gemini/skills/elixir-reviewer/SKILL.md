---
name: elixir-reviewer
description: Triggers when executing code reviews on Elixir files, mix setups, or supervisor structures.
---

# Elixir Review Guidelines
When analyzing code changes, the agent must check for:
- Proper Supervision tree architecture.
- Credentials or secrets checked into code.
- Clean implementation of GenServers and Ecto queries.

# Erlang VM & Stability Rules
- **NO GenServer Crashes**: A crash must not take down a child node.
- **State Integrity**: Mnesia data (tickets, users) must survive crashes and node restarts.
- **Libcluster Sync**: Ensure mesh discovery is healthy before accepting writes.

# Mnesia Specific Rules
- **Replication**: Ensure `mnesia_db` is replicated across nodes if data is critical.
- **Backup**: How often is the Mnesia dump backed up to disk/Postgres?
- **Schema**: Verify `mnesia_schema` is migrated correctly.

# Performance Rules
- **Avoid :mnesia.all_keys() in loops**: Use `match_object` or specific lookups.
- **Distributed Transactions**: Ensure heavy operations use `!transaction` (atomic) not `:transaction` (sync) if performance is critical.
- **Type Mismatches**: Handle Erlang tuple indexing (`elem(record, 8)`) carefully.

# Security Rules
- **No Hardcoded Secrets**: Never commit API keys, passwords, or tokens.
- **Permissions**: Verify database roles and access levels are minimal (Principle of Least Privilege).
- **Data Sanitization**: Ensure user inputs are sanitized before being written to Mnesia or Postgres.

# Compatibility Rules
- **Erlang/Elixir Version**: Ensure compatibility with the project's `OTP_VERSION` and `ELIXIR_VERSION`.
- **Ecto**: Ensure Ecto queries are compatible with the current DB schema (Postgres/Mnesia).

# Best Practices
- **Testing**: Verify unit and integration tests exist for new features.
- **Documentation**: Ensure `README.md` and relevant docs are updated.
- **Linting**: Run `mix format` and `mix xref` to check for issues.
