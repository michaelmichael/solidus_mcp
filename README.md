# Solidus MCP

A self-contained Rails engine for administering a Solidus store through MCP.
The gem owns its standard tools, serializers, authorization, Streamable HTTP
endpoint, OAuth integration and optional SolidusAdmin connection controls.
No host-defined handlers or resource declarations are required.

## Supported environment

The test matrix targets Ruby 3.2, Rails 8.0, Solidus 4.7, PostgreSQL 17,
Doorkeeper 5.9 and MCP Ruby SDK 1.8.1. SolidusAdmin 0.4 is optional.
Other Solidus versions and custom pricing-option implementations are not claimed
as supported. The pricing tools explicitly reject custom pricing classes; those
stores can register their own pricing tool.

## Initial installation

Add the gem at a tested immutable revision or release, install dependencies,
and install Doorkeeper's standard tables if your application does not already
have them (`bin/rails generate doorkeeper:install` and
`bin/rails generate doorkeeper:migration`). Do not generate a second set of
OAuth tables in an existing installation.

Configure once in an initializer:

```ruby
SolidusMcp.configure do |config|
  config.endpoint_url = ENV.fetch("SOLIDUS_MCP_ENDPOINT_URL") # https://store.example/mcp
  config.issuer_url = ENV.fetch("SOLIDUS_MCP_ISSUER_URL")     # https://store.example
  config.allowed_origins = ["https://your-browser-client.example"]
  # Optional: class names only, never standard tool registrations.
  config.custom_tools = ["MyStore::SpecialLookup"]
end

# Use only if this engine is configuring Doorkeeper for this application.
SolidusMcp::Oauth.configure!
```

Omit `custom_tools` if none are needed. For an application already using
Doorkeeper, merge the settings from `SolidusMcp::Oauth.configure!` into its
existing configuration once instead of configuring Doorkeeper twice. Preserve
existing clients, secret-hashing behavior and resource columns. The required
settings include authorization-code flow, S256 PKCE, hashed token/client secrets,
refresh tokens, stable scopes and `custom_access_token_attributes [:resource]`.
The engine does not silently replace application-wide OAuth configuration.

The default resource-owner authentication uses Solidus's `:spree_user` Warden
session and `/admin/login`. A store using different authentication can provide
`config.resource_owner_authenticator = -> { ... }`; return the authenticated
Solidus user or render/redirect. The returned user must be an administrator.
Use a shared Rails cache store for registration rate limits in multi-process
production installations.

Mount the engine and expose issuer discovery before catch-all routes:

```ruby
mount SolidusMcp::Engine => "/mcp"
get "/.well-known/oauth-authorization-server", to: "solidus_mcp/metadata#authorization_server"
get "/.well-known/oauth-protected-resource/mcp", to: "solidus_mcp/metadata#resource"
```

These discovery examples assume a root issuer and `/mcp` endpoint. Adjust the
well-known route paths once if choosing different canonical paths. The
unauthorized endpoint also advertises its resource metadata URL in
`WWW-Authenticate`. Metadata and OAuth URLs come from configured canonical URLs,
never untrusted request headers. Keep the engine mount and configured endpoint
consistent. Configure Rails host authorization as usual.

Run host migrations first, then engine migrations:

```sh
bin/rails db:migrate
bin/rails solidus_mcp:migrate
```

The second command runs migration files directly from the installed gem with
Rails' normal migration tracking and locking. Add it to the release process
once. There is no need to copy engine migrations into the host repository on
every release. Alternatively, conventional `solidus_mcp:install:migrations`
remains available, but requires managing copied files.

Start the app, connect an OAuth client, then enable individual tools in
SolidusAdmin **AI connections**. New connections have no tool permissions.
Delete a permission set from its edit screen to clear all grants, disable access
and move it out of the active list. Deleted permission sets retain their audit
history and can be explicitly restored. Deletion does not revoke OAuth tokens
or remove the client registration; execution stays denied until restored.

Without SolidusAdmin, a trusted host administrative process can use
`ConnectionPolicy#change!`; permission management is never an MCP tool.

## Built-in tools

| Category | Tools |
| --- | --- |
| Products | `search_products`, `get_product`, `get_product_variants`, `create_product`, `update_product` |
| Pricing | `get_variant_prices`, `update_variant_price`, `bulk_update_variant_prices` |
| Inventory | `get_inventory_levels`, `search_inventory` |
| Orders | `search_orders`, `get_order`, `get_order_status` |

All tools are registered automatically by the engine. `tools/list` returns the
catalog permitted to the current credential, including exact input schemas.
Categories are admin labels, not MCP resources. Searches have bounded keyset
pagination (`after_id`, `limit`, maximum 100). Order detail includes at most 100
authorized line items and indicates truncation; payment credentials and customer
contact details are not serialized.

`create_product` creates an unavailable draft with required `name` and numeric
`price` (zero or greater). Supply `shipping_category_id`, or configure a store
default in the initializer:

```ruby
SolidusMcp.configure do |config|
  category_id = ENV["MCP_DEFAULT_SHIPPING_CATEGORY_ID"].presence
  config.default_shipping_category_id = Integer(category_id) if category_id
end
```

The explicit ID takes precedence; a missing or nonexistent category fails without
creating a product. The tool checks Solidus creation permissions against the new
product before saving and returns `{product_id: ..., created: true}`. Enable the
`create_product` connection permission and authorize `mcp:write` to expose it.
Additional variants and inventory are outside this tool's scope.

`update_product` accepts only `name`, `description`, `meta_title`,
`meta_description` and `meta_keywords`. It uses Solidus validation and checks
both the existing and proposed record. There are no order or inventory mutations.

Pricing inputs use decimal strings, explicit currency and explicit `country_iso`
(`null` means the general-country row). The single tool takes `variant_id`;
the bulk tool takes up to 100 entries with `sku`, `amount`, `currency` and
`country_iso`. Both update an existing exact price row using normal Solidus
validation and a row lock. They never create a price or silently fall back to
another context. Amounts must fit Solidus's two-decimal price column.

Bulk results preserve entry order and include `index`, `sku`, `success`, and
`price` or `error`. Business failures are isolated per entry. Duplicate targets,
missing/ambiguous SKUs and missing/ambiguous price contexts fail explicitly.
Malformed request structure is rejected before execution. There is no preview,
approval, automatic retry or all-or-nothing bulk transaction.

## Authorization

Every invocation requires an active, audience-bound credential, an enabled
connection, the tool's unique permission, its OAuth scope, the user's Solidus
abilities and authorization for each accessed record. Connection policies are
keyed by OAuth application and user, so token refresh retains grants. Permission
changes and connection disablement are checked at execution, including cached
SDK tool objects. Bulk execution rechecks authorization for each entry and again
inside its price lock. Already committed changes are not undone by a later
permission revocation.

Scopes are independent:

- `mcp:read` authorizes enabled read tools.
- `mcp:write` authorizes enabled write tools.

Clients wanting both can request both. For clients without scope controls, the
consent page provides **Need additional access?**: select the desired access,
click **Review access**, then review and **Authorize**. Extra access is unchecked
unless requested. Reviewing issues no code or token and preserves the client's
state, callback, resource and PKCE challenge. Only scopes allowed by the client
registration are offered; read-only registrations cannot be upgraded here.
The consent summary displays the selected scopes; write is never silently added
to a read-only request. Client registration's permitted scopes are a ceiling,
not a grant. A write-only token does not imply read scope.
An administrator can enable a write permission on a read-only connection, but
it remains ineffective and the UI explains the missing OAuth authorization.

A permitted tool blocked only by token scope receives HTTP 403 with the standard
`insufficient_scope` challenge. Clients that support step-up authorization can
start another OAuth flow; otherwise reconnect through the client requesting the
needed scopes. Token refresh cannot increase access. Disabling a tool requires
an admin change, not another consent flow. Refresh client discovery after grants
change; stateless transport does not push catalog-change notifications.

Permissions are unique per tool. New tools never inherit another tool's grant.
If a tool's behavior expands beyond its existing permission's meaning, release
it with a new permission key. Retired permission keys must not be reused for
unrelated capabilities. Unknown historical keys remain inert and audit history
is retained. Administrators cannot add arbitrary unknown keys.

## Custom tools

Put a named subclass in `app/tools/my_store/special_lookup.rb`:

```ruby
module MyStore
  class SpecialLookup < SolidusMcp::Tool
    tool_name :special_lookup
    description "Look up a store-specific product label."
    category "Custom"
    permission "my_store.special_lookup"
    read_only true
    ability :read, "Spree::Product"
    input :product_id, type: "integer", minimum: 1, required: true

    protected

    def call(product_id:)
      product = policy.scope(Spree::Product).find(product_id)
      policy.authorize_record!(:read, product)
      {id: product.id, label: product.name}
    end
  end
end
```

Register its class name in `config.custom_tools`. The engine adds custom tools
to its standard catalog and rejects collisions. The shared `.execute` entry
point enforces schema and authorization for MCP and direct Ruby callers:

```ruby
MyStore::SpecialLookup.execute(credential: credential, product_id: 123)
```

Implement `call` as protected. Declare all class-level abilities and check all
related records and proposed changes in the implementation. Collection scopes
and explicit serializers are still the tool author's responsibility. Trusted
custom Ruby code is not sandboxed. Class names and schemas are rebuilt in Rails'
`to_prepare`; reloadable classes are not retained in a global registry.

## Development baseline

Version 0.2 is the canonical implementation. The earlier unpublished host
registry and handlers are retired; their APIs and tool catalog are not supported.
Use this engine's built-in tools and custom-tool API for all new work. Hosts
should mount the engine directly and remove duplicate MCP controllers, handlers,
serializers and registry configuration. There is no compatibility mode.

Tool permission keys and read/write consent are explicit. Newly added tools
start disabled. Standard tool additions and changes belong in this repository;
the host only supplies configuration and any genuinely store-specific tools.

## Releases without Store API commits

The application still embeds the engine: a release needs a new application image
and process restart. It does not need a Store API source commit for each gem
release after a one-time build integration.

Allow the build to select an immutable MCP commit/release outside the Store API
repository. Resolve only that dependency in a disposable build workspace, retain
the resulting lockfile with the artifact, and reject unrelated dependency changes
unless explicitly reviewed. An environment-variable Git ref alone is insufficient:
the existing frozen lockfile must also be deliberately updated during the build,
and the resulting lockfile must not be overwritten by a later Docker `COPY`.

Record the Store API commit, MCP commit, resolved lockfile and image digest. Run
the gem suite plus focused host boot/OAuth/tool/migration checks before promotion.
Use broader store tests when dependencies or schema changes warrant them. Roll
back the image using its recorded inputs; migrations must remain compatible with
the previous image during rolling deploys. Production never follows a moving
branch or updates a running bundle. This repository does not trigger deployment
or change Store API's build configuration automatically.

## Local development

```sh
docker compose run --rm test
docker compose down
```

`bin/ci` migrates a disposable database using the real Solidus migrations, runs
specs, verifies actual development reloading and production eager loading, checks
Ruby style, and builds the gem. The test application contains only fixture users
and configuration, never Store API handlers or production credentials. Its
non-test modes require the explicit loading-check flag and are not deployable.
CI also tests a core-only install with `WITHOUT_ADMIN=1`. Run the same checks
locally before pushing; GitHub CI is final verification, not the development loop.
