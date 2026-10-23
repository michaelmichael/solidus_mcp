# Solidus MCP

A resource registry, connection permission controls, and capability discovery
for MCP servers embedded in Solidus. This is the first implementation and is not yet published to RubyGems.

## What it provides

- Explicit resources and named permissions such as `products.read`,
  `products.update`, and `products.publish`.
- A tool registry connecting schemas, OAuth scopes, required permissions and
  fixed Ruby handlers.
- Permissions for each OAuth application/user pair, retained across token
  refreshes and checked during discovery and execution.
- A SolidusAdmin **AI connections** screen, with connection disablement,
  optimistic locking and transactional permission-change audits.
- `list_capabilities` and `describe_resource`, generated from the caller's
  permitted tools.
- Solidus ability checks and helpers for authorizing records and scoping queries.

The host owns OAuth setup, the HTTP endpoint, business handlers and serializers.
The engine does not expose ActiveRecord models or Ruby methods automatically.
It uses the official Ruby MCP SDK for the protocol.

## Current compatibility

The standalone test suite targets Solidus 4.7, SolidusAdmin 0.4 (optional),
Rails 8.0, Ruby 3.2 and PostgreSQL 17, with Doorkeeper and the MCP Ruby SDK.
PostgreSQL is required by the JSONB migration and the admin token-expiry query.
The admin screen requires SolidusAdmin; the first version is for administrators.
CI tests both admin-enabled and core-only installations. Other version combinations
are not yet in the supported test matrix.

## Install in a host application

Install from GitHub (access to the private repository is currently required):

```ruby
gem "solidus_mcp", git: "https://github.com/michaelmichael/solidus_mcp.git", branch: "main"
```

```sh
bundle install
bin/rails solidus_mcp:install:migrations
bin/rails db:migrate
```

Configure Doorkeeper and an authenticated MCP endpoint in the host. The engine
expects its default `oauth_applications` table and resource owners that are
Solidus users. It adds routes to the existing SolidusAdmin engine:
`/admin/mcp_connections` when that engine is mounted at `/admin`.

## Register a resource and tool

Build and replace the registry in a `to_prepare` callback, so development reloads
do not retain old handler classes. Class names below come from trusted code.

```ruby
Rails.application.config.to_prepare do
  registry = SolidusMcp::Registry.new
  registry.resource :products,
    model: "Spree::Product", label: "Products",
    actions: {read: :read, publish: :update}

  registry.tool :publish_product,
    resource: :products,
    permissions: ["products.publish"],
    definition: {
      scope: "products:write",
      read_only: false,
      description: "Publish a prepared product.",
      properties: {product_id: {type: "integer", minimum: 1}},
      required: ["product_id"]
    },
    handler: "MyStore::Operations"

  SolidusMcp.registry = registry.seal!
end
```

The handler must accept a credential in its constructor and implement the named
method with keyword arguments. A credential provides `user`, `token`, `active?`
and `permits?(oauth_scope)`. The token supplies `application_id`.

Build a protocol server for each authenticated request:

```ruby
server = SolidusMcp::Server.build(
  credential: credential,
  name: "my-store", version: "1.0.0",
  instructions: "Store administration.",
  errors: [MyStore::Operations::Error]
)
```

Use the SDK's Streamable HTTP transport to serve it. The host is responsible for
token validation, resource audience, origin validation and OAuth consent.

## Authorization contract

A tool requires an active credential, all its OAuth scopes, all its connection
permissions and the user's corresponding Solidus abilities. A permission's
`actions` value maps it to an ability, e.g. `publish: :update` checks
`Spree::Ability#can?(:update, Spree::Product)`.

Class checks only determine which tools may be offered. Handlers must use
`Policy#scope(model)` for collections and `Policy#authorize_record!(action,
record)` for individual records, related records, and proposed create/update
values. Handlers must explicitly declare all resources their output includes.
The engine does not infer authorization for business side effects, callbacks or
serialized associations. Mutation handlers remain responsible for transactions,
business invariants, audits, concurrency guards and idempotency.

For services callable outside the protocol, call `Policy#authorize!` at the
service entry point too. The small example handlers in `spec/support/test_catalog.rb` demonstrate
this contract; real stores provide their own business operations.

Every new installation defaults to **no connection permissions**. Once a user
has connected, an administrator can enable registered permissions through the
admin screen. A host migrating an existing server can explicitly set
`SolidusMcp.default_permissions` to a fixed list of existing permission keys.
Do not derive that list from the registry: doing so grants future additions.
Saved policies always override defaults, including an empty permission list.

Saving the first policy snapshots the selected permissions. A newly registered
permission is denied until deliberately granted; a new tool using an existing
permission inherits that permission's meaning. OAuth scopes remain an additional
ceiling, so checking a box cannot expand an existing token's scopes.

Administration requires a browser session, CSRF protection, the Solidus ability
to manage `:mcp_connections`, and an administrator account. Permission management
is never registered as an MCP tool. Policy edits and their actor-attributed
audits share a database transaction. Tokens and secrets are not shown in the UI.
Policies retain the application's UID and actor/user IDs so deleting an OAuth
registration does not delete its permission-change history.

## First-release boundaries

This version provides resource/operation controls for explicitly registered
handlers. Field restrictions are the fixed input schemas and serializers defined
by the host; per-connection field selection, reusable role profiles, generic CRUD
adapters, and a separate approval workflow are not implemented. Deletes are
available only if a host deliberately implements and registers them. A preview
is a business-handler feature, not proof of human approval.

Store-specific ownership rules, pricing rules and custom fields belong in the
host adapter.

## Development and verification

The extension directory is self-contained: it includes its own Gemfile, minimal
Rails test application, specs, Docker setup and GitHub Actions workflow. It does
not load a parent repository, its environment files, or store credentials.

With Docker, from this directory:

```sh
docker compose run --rm test
docker compose down
```

PostgreSQL data is temporary; the bundle cache is kept in a separate named volume.
The default command installs dependencies, migrates a blank test database, runs
the specs and Ruby style checks, and builds the gem.

With Ruby 3.2 and PostgreSQL 17 installed:

```sh
export DATABASE_URL=postgresql://postgres:postgres@localhost:5432/solidus_mcp_test
bin/ci
```

Use a disposable database. The dummy app only boots in `test` and creates fixture
users, catalog entries, standard Doorkeeper tables, and the engine's real policy
and audit tables. It uses Solidus's real ability system, the MCP SDK, and the
engine's real admin controller and forms. Its test-only header authentication
and simplified page layout are fixtures, not a store authentication recipe.
Full store OAuth transport and browser/layout tests belong in host applications.

To check the optional-admin boundary locally:

```sh
WITHOUT_ADMIN=1 bundle install
WITHOUT_ADMIN=1 bundle exec rspec --exclude-pattern 'spec/requests/**/*_spec.rb'
```

The standalone workflow is `.github/workflows/ci.yml`. While embedded in the
store repository, a root workflow runs the same checks from this directory.
See [CONTRIBUTING.md](CONTRIBUTING.md) for the test and release process.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
