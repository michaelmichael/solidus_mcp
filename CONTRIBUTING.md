# Contributing

Develop and test locally before pushing a cohesive change. `bin/ci` runs the
same checks used in CI; `docker compose run --rm test` provides Ruby/PostgreSQL.
Use only a disposable database. No store checkout or production credentials are
required.

CI checks Rails 7.2 and 8.0 on Ruby 3.2, with and without Solidus Admin. To
select a Rails version locally, set `RAILS_VERSION='~> 7.2.0'` or
`RAILS_VERSION='~> 8.0.0'` when resolving dependencies and running checks.
Set `WITHOUT_ADMIN=1` for the core-only suite. The default is Rails 8.0 with
Solidus Admin. Use separate disposable databases when testing fresh migrations.

Tests exercise real Solidus 4.7 models, engine-owned tools and transport,
Doorkeeper consent/PKCE/refresh, record authorization, explicit per-tool grants,
admin audits/locking/CSRF, mixed bulk results, custom tools, catalog upgrades,
and actual development reloading and production eager loading.

Add built-in classes to `SolidusMcp::BUILTIN_TOOLS` inside the gem. Never add host
registration requirements. Each tool needs a unique permission; changed behavior
that broadens an existing grant needs a new key. Do not reuse retired permission
keys. Include negative tests for changes to authorization, inputs or serializers.

The direct migration command is `bin/rails solidus_mcp:migrate` after host
migrations. Keep migrations immutable and safe alongside the previous release.
Do not run down migrations automatically during deployment rollback.

For release, run admin and core-only suites, both loading checks, style checks,
and gem packaging locally. Review the package and changelog. Preserve immutable
build inputs and verify the real host integration before production promotion.
Publishing, pushing, tagging and deployment remain deliberate separate actions.
