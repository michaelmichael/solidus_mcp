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

## Releasing

Pushing a version tag triggers `.github/workflows/release.yml`. The workflow
requires the tag to match `SolidusMcp::VERSION` exactly (for example,
`v0.2.0.rc2`) and its commit to be on `main`. It runs the full Rails/admin CI
matrix before building and publishing the gem to RubyGems. Ordinary branch pushes
and pull requests do not publish. The built gem is retained as a workflow artifact.
Publishing does not update or deploy any host application.

### One-time setup

1. In this repository's GitHub **Settings > Environments**, create `rubygems`.
   Restrict its deployment tags to `v*`; optionally require a release reviewer.
   Allow version tags to be created only by release maintainers using a GitHub
   tag ruleset. Tagged code executes in the publishing workflow, so access to
   create release tags is release authority.
2. On RubyGems.org, open the `solidus_mcp` gem's **Settings > Trusted Publishers**
   and add a GitHub Actions publisher with these exact values:
   - Repository owner: `michaelmichael`
   - Repository name: `solidus_mcp`
   - Workflow filename: `release.yml`
   - Environment: `rubygems`

The workflow uses OIDC to obtain short-lived publishing credentials. Do not add
a `RUBYGEMS_API_KEY` or other long-lived publishing secret to GitHub. The
`id-token: write` permission is limited to the publishing job, after tests pass.

### Each release

1. Bump `lib/solidus_mcp/version.rb` and move the applicable `CHANGELOG.md`
   entries into a section for that version.
2. Run `bin/ci` (or `docker compose run --rm test`) and review the package and
   changelog. Merge the version change into `main` and wait for CI to pass.
3. From a clean checkout of the merged `main` commit, create and push the tag:

   ```bash
   git switch main
   git pull --ff-only
   test -z "$(git status --porcelain)"
   version=$(ruby -r ./lib/solidus_mcp/version -e 'print SolidusMcp::VERSION')
   git tag -a "v${version}" -m "Release ${version}"
   git push origin "v${version}"
   ```

4. Watch the **Release gem** workflow, approve the `rubygems` deployment if
   required, and verify the new version on RubyGems.org before updating hosts.

Do not move a published tag or try to replace a published gem. Fixes need a new
version. A failed run can be re-run if publishing never succeeded; if the gem is
already on RubyGems, do not re-run the publish job (RubyGems rejects duplicates).
Verify the real host integration before production promotion.
