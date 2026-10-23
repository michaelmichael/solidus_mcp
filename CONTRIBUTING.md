# Contributing

Run `bin/ci` against a disposable PostgreSQL database, or use
`docker compose run --rm test`. Both commands run migrations, specs, Ruby style
checks and gem packaging. No store checkout, private gems or secrets are needed.

## Tests

- `spec/registry_spec.rb`: registration, unknown grants and immutable schemas.
- `spec/policy_spec.rb`: default denial, scope/ability ceilings, record scoping,
  token lifecycle, isolation and policy changes.
- `spec/server_spec.rb`: MCP discovery and real SDK execution, including denial
  after a server has already been built.
- `spec/requests/connections_spec.rb`: admin authorization, rendered forms, CSRF,
  concurrency and atomic audit history.

The dummy app deliberately contains only the host contracts used by the engine.
Do not copy production schemas, credentials or store handlers into it. Its
identity header is only for request tests, and its application refuses to boot
outside test. A real host must supply authenticated credentials and record-aware
business handlers.

When adding a permission or changing authorization, include a denial test. Keep
new installations default-deny; never generate compatibility defaults from all
registered permission keys. Changes to discovery must also be enforced during
execution.

CI uses a fresh PostgreSQL 17 database and runs the Rails 8.0 / Solidus 4.7 suite
on Ruby 3.2 with and without SolidusAdmin 0.4. Broader compatibility should only
be advertised after adding and running the corresponding jobs.

## Preparing a release

1. Run CI and review the source archive and gem contents.
2. Update the changelog and version together. Build with
   `gem build solidus_mcp.gemspec` and test installation in a clean host.
3. Publish releases deliberately. This repository is initially private; the
   included workflow does not change visibility, push tags or publish packages.
