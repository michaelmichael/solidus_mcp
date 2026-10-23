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
      scope: "mcp:write",
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

## One class per tool

The class interface keeps a tool's metadata, inputs and implementation together.
The existing `registry.tool` handler interface remains supported. For example,
place this class in `app/tools/my_store/products/publish.rb`:

```ruby
module MyStore
  module Products
    class Publish < SolidusMcp::Tool
      tool_name :publish_product
      resource :products
      permissions "products.publish"
      scope "mcp:write"
      description "Publish a prepared product."
      read_only false
      input :product_id, type: "integer", minimum: 1, required: true

      def call(product_id:)
        authorize!
        # Delegate to a host service that checks records and proposed changes,
        # enforces business rules, and performs the transaction and audit.
        MyStore::Operations.new(credential).publish_product(product_id: product_id)
      end
    end
  end
end
```

Register it after declaring its resources:

```ruby
Rails.application.config.to_prepare do
  registry = SolidusMcp::Registry.new
  registry.resource :products, model: "Spree::Product", label: "Products",
    actions: {publish: :update}
  registry.register MyStore::Products::Publish
  SolidusMcp.registry = registry.seal!
end
```

`input` accepts JSON Schema keywords; `required: true` adds the input to the
object's required list. `scope` and `permissions` accept multiple strings.
All tools must explicitly declare `read_only`, scopes and permissions. Tool
classes must be named subclasses with a public `call` method. Registrations
snapshot and freeze schemas, retain class names for Rails reloading, and pass
through the same validation as `registry.tool`.

Each invocation gets a new handler with `credential` and `policy` accessors.
The server always authorizes before calling the handler. Call `authorize!` at
the start of `call` as well if the class is used directly by application code.
This does not replace record checks: use `policy.scope` and
`policy.authorize_record!` for records, related records and proposed changes.

For an incremental migration, `SolidusMcp::Server.tools(credential:, errors: [])`
returns policy-protected SDK tools plus the two capability tools. A host may
combine them with existing tools in its own `MCP::Server`. Remove migrated tools
from the old list to avoid duplicate names. Capability discovery only describes
registry tools, and registry permissions do not protect any legacy tools left
outside it. Prefer `SolidusMcp::Server.build` once all tools are registered.

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

## Delete a connection

Open **AI connections**, choose **Edit permissions**, then **Delete connection**.
Deletion revokes all access/refresh tokens and pending authorization codes for
that application/person pair, clears permissions, and disables the policy. The
connection disappears from the list. Shared OAuth registrations and other
people's connections are unaffected. Revoked token rows and policy history are
retained for auditing. A new authorization can reconnect the same client, but
its permissions stay disabled until an administrator explicitly enables them.
The list includes application IDs to distinguish repeated client registrations.

## Broad OAuth consent and tool permissions

For hosts that want tool changes without repeated OAuth consent, use stable
`mcp:read` and `mcp:write` scopes and keep individual permissions in the registry.
New permissions remain disabled until an administrator enables them. Write
consent must clearly cover write tools enabled later. Read-to-write upgrades
still require a new authorization request and explicit consent.

The host owns OAuth discovery, registration and consent. Default authorization
to read-only, allow write only through consent, and validate requested scopes
against the client's registration. Checking an AI connection permission never
changes a token's scope ceiling. Refresh the client's tools after permission
changes; execution rechecks permissions even if a client caches its listing.

For a host migrating existing narrow scopes, configure explicit one-way
implications and use the same helper in its credential:

```ruby
SolidusMcp.scope_implications = {
  "mcp:read" => %w[catalog:read sales:read].freeze,
  "mcp:write" => %w[mcp:read products:write prices:write inventory:write].freeze
}.freeze

# In the host credential:
def permits?(scope)
  SolidusMcp::OauthScopes.permits?(token.scopes.to_a, scope)
end
```

New tool classes can declare `scope "mcp:read"` or `scope "mcp:write"`. Existing
tool declarations may retain their narrow requirements during migration: broad
tokens cover them, while legacy tokens keep their original limits. Do not infer
implications from the registry or map narrow grants back to broad write access.
Without configuration the helper uses exact scope matching. Empty scopes grant
nothing. Implications are also used by admin connection warnings, with each
active token assessed separately; complementary tokens are never combined.

Keep legacy scopes accepted for existing clients and refresh grants. Do not
silently widen tokens or client registrations. Clients registered with only old
scopes need an explicit registration update or new registration and one consent
flow to adopt broad scopes. New registrations also need their own connection
permissions. Migrating previously unregistered tools into the registry requires
administrators to grant their new permissions; do not enable them automatically.

## OAuth scopes and reconnecting

A tool still requires both consent and connection permissions. The admin screen
warns when active tokens lack its required scopes, but cannot initiate the
client's PKCE authorization flow itself. Configure host-specific instructions:

```ruby
SolidusMcp.reconnect_instructions =
  "Reconnect from your client to upgrade from read to write. On the store " \
  "consent screen, select write access, review the permissions, then Authorize."
```

Hosts can offer a scope chooser on the consent page when clients have no scope
setting. Keep additional scopes unchecked, restrict choices to the registration,
preserve state, callback, resource and PKCE challenge, and show the revised
consent before issuing a code. Do not ask users to edit OAuth URLs. A token
refresh cannot increase scopes. Mixed active tokens may retain warnings until
the older tokens expire or are revoked.

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
