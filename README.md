# Solidus MCP

## Overview

Solidus MCP provides an MCP server for managing and administering Solidus storefronts.

It comes with a set of built-in tools to get you started. Connected agents can look up products and orders, update pricing, and check inventory.

With Solidus, customization is king, so you aren't limited to the built-in tools. You can add your own MCP tools to support your specific store and workflows.

The default install runs inside your store. It provides the MCP server and OAuth integration with Doorkeeper.

A permission system allows for granular control. Any Solidus admin can connect to the MCP server, but has no access to tools by default. MCP admins can grant and revoke tool access for ordinary MCP users. Only superadministrators can manage privileged connections or elevate users to MCP administrators.

Superadministrators are designated through server-side configuration, outside the store’s user interface. This lets you delegate MCP permission management without giving administrators the ability to promote themselves or others.

## Requirements

Solidus MCP requires Ruby 3.2 or newer and Rails 7.2 or 8.0. Both Rails versions are tested with Ruby 3.2, Solidus 4.7, PostgreSQL 17, Doorkeeper 5.9, and MCP Ruby SDK 1.8.1.

Solidus Admin 0.4 integration allows users to administer accounts and permissions in the default Solidus Admin interface. It is optional; the MCP server can run without it, but you'll need to manage connection grants through trusted application code.

## Installation

These instructions assume you already have a working Solidus application. If your store already uses Doorkeeper, read [Integrating with existing Doorkeeper](#integrating-with-existing-doorkeeper) before configuring OAuth.

### 1. Install the gem

Add the gem to your `Gemfile`:

```ruby
gem 'solidus_mcp', '0.2.0.rc2'
```

Then run:

```sh
bundle install
```

This is a release candidate. Keep `Gemfile.lock` under version control so deployments use the reviewed dependency versions.

### 2. Generate the Doorkeeper migration

The gem installs Doorkeeper for OAuth, but it does not automatically install its database tables:

```sh
bin/rails generate doorkeeper:migration
```

Skip this command if your app already has the standard Doorkeeper tables or a pending migration to create them. You don't need `doorkeeper:install` for a fresh setup: the initializer below supplies the OAuth configuration, and the engine supplies the routes.

### 3. Set environment variables

For local testing:

```dotenv
SOLIDUS_MCP_ENDPOINT_URL=http://localhost:3000/mcp
SOLIDUS_MCP_ISSUER_URL=http://localhost:3000
SOLIDUS_MCP_SUPERADMIN_EMAILS=owner@example.com
```

For a deployed store, use your public HTTPS URLs instead:

```dotenv
SOLIDUS_MCP_ENDPOINT_URL=https://www.mystore.com/mcp
SOLIDUS_MCP_ISSUER_URL=https://www.mystore.com
SOLIDUS_MCP_SUPERADMIN_EMAILS=owner@example.com,security@example.com
```

The endpoint URL must match the mount path you'll add to `config/routes.rb`. The issuer is the base URL of the app hosting the server.

Superadministrator emails must match existing Solidus admin accounts. The gem reads this variable automatically. The two URL variables are read by the initializer in the next step.

### 4. Create the initializer

Create `config/initializers/solidus_mcp.rb`:

```ruby
SolidusMcp.configure do |config|
  config.endpoint_url = ENV.fetch('SOLIDUS_MCP_ENDPOINT_URL')
  config.issuer_url = ENV.fetch('SOLIDUS_MCP_ISSUER_URL')
  config.allowed_origins = []
end

SolidusMcp::Oauth.configure!
```

An empty `allowed_origins` list works for clients that send no `Origin` header. For browser clients, add the exact origins they use, including the scheme and port. For example, a local MCP Inspector may need:

```ruby
config.allowed_origins = ['http://localhost:6274', 'http://127.0.0.1:6274']
```

Use the origin from the actual request, not the address of the MCP endpoint. Requests carrying an unlisted origin return 403.

The default OAuth configuration authenticates through Solidus's `:spree_user` Warden scope and sends unauthenticated users to `/admin/login`. Stores with custom authentication can supply a `config.resource_owner_authenticator` block returning the signed-in Solidus user.

MCP access still requires Solidus admin status.

### 5. Add routes

Add these routes to `config/routes.rb`, before your storefront mount or any catch-all routes:

```ruby
Rails.application.routes.draw do
  mount SolidusMcp::Engine => '/mcp'
  get '/.well-known/oauth-authorization-server',
    to: 'solidus_mcp/metadata#authorization_server'
  get '/.well-known/oauth-protected-resource/mcp',
    to: 'solidus_mcp/metadata#resource'

  # Your existing admin and storefront routes follow.
end
```

Rails host authorization must also allow the hostname used to reach your app.

### 6. Run migrations and restart

With your environment variables loaded, run:

```sh
bin/rails db:migrate
bin/rails solidus_mcp:migrate
```

The first command runs your app's migrations, including the generated Doorkeeper migration. The second runs the gem's migrations directly from the installed gem. These add connection permissions and audits, OAuth resource and PKCE attributes, and MCP administrator assignments.

### 7. Verify the endpoint

For a local server on port 3000:

```sh
curl -i http://localhost:3000/.well-known/oauth-authorization-server
curl -i http://localhost:3000/.well-known/oauth-protected-resource/mcp
curl -i http://localhost:3000/mcp
```

The discovery requests should return 200 with JSON describing the issuer, OAuth endpoints, resource URL, and supported scopes. The unauthenticated MCP request should return 401 with a `WWW-Authenticate` header pointing to resource metadata. That 401 is expected: the endpoint requires an OAuth token.

## Connect a client

Choose **Streamable HTTP** as the transport and enter your endpoint URL, such as `http://localhost:3000/mcp`.

Use a client that supports OAuth discovery, dynamic client registration, and S256 PKCE. Follow its authorization flow, sign in with a Solidus admin account, and approve the requested scopes. Being signed into the store in a browser does not authenticate the MCP client; it needs its own OAuth token.

The scopes are independent:

- `mcp:read` allows read tools when the connection has permission for them.
- `mcp:write` allows write tools when the connection has permission for them. It does not include read access.

If the client initially requests only read access, review and request write access before testing write tools. An administrator granting a write permission cannot expand an existing token's scopes. Refreshing a token also cannot add scopes beyond its original authorization.

## Enable tools

New connections start with no tool permissions, including connections owned by superadministrators.

1. Sign into Solidus Admin as a configured MCP superadministrator.
2. Open **AI connections** and select the client's connection for the intended user.
3. Enable a read tool, such as `search_products`, and save.
4. Refresh the client's tool list or reconnect, then ask it to find a product in your store.

The permission table lets you select individual tools, a whole category, or all permissions. Start with the tools the connection needs. Test writes against disposable data before granting access to live store changes.

Permission changes apply on subsequent calls. Clients may cache their tool lists, so refresh discovery after changing grants. Disabling a connection blocks requests made with its existing tokens. Deleting a permission set disables it and retains its audit history; it does not delete the OAuth client or its tokens. To use it again, restore and enable it from **Deleted sets**.

## Administration

All three levels require a Solidus admin account:

| Level | Can do |
| --- | --- |
| MCP user | Connect clients, use assigned tools, and view their own connections. |
| MCP administrator | Manage ordinary MCP users' connection grants. Their own connections are read-only; other privileged users' connections are hidden. |
| MCP superadministrator | Manage all connections, including their own, and assign or remove MCP administrators. |

To assign an MCP administrator, open **AI connections → Manage MCP administrators** as a superadministrator. Search by login email, choose an existing Solidus admin, and assign access. The same screen lets you remove or restore assignments.

These assignments belong to the gem. Adding a Solidus role named `mcp_admin` does not grant MCP administration rights. Removing an MCP administrator assignment removes management authority, but retains that user's existing connection tool grants.

Every tool call must pass the connection grant, OAuth scope, and Solidus ability checks. Tools must also respect record-level access. Administration roles do not bypass these checks.

The hierarchy depends on your store's account security. Restrict who can change privileged accounts' emails, reset their passwords, or impersonate them. Someone who can take over a superadministrator's account can act as that superadministrator.

See [MCP administration hierarchy](docs/administration.md) for configuration details, audit behavior, and management APIs for stores without Solidus Admin.

## Integrating with existing Doorkeeper

Reuse your existing OAuth tables and initializer. Do not call `SolidusMcp::Oauth.configure!` on top of an existing configuration: Doorkeeper is application-wide, and that helper is intended for a fresh installation.

Merge the MCP requirements into your existing configuration instead. Use [the helper's implementation](lib/solidus_mcp/oauth.rb) as a reference:

- Authorize Solidus admin users through your existing login flow.
- Support authorization-code grants, S256 PKCE, and refresh tokens.
- Add `mcp:read` and `mcp:write` to your configured scopes and enforce configured scopes.
- Include `:resource` in `custom_access_token_attributes`, preserving any other attributes.
- Use token and application secret hashing, accounting for existing clients and stored credentials before changing those settings.
- Allow literal loopback HTTP callbacks for local clients while requiring HTTPS for other callbacks.

Run the engine migrations after your host migrations. They add the required resource and PKCE columns without removing existing columns. Mount the engine as shown above; keep routes for your other OAuth integrations in place.

Check your existing integrations before deploying changes to shared OAuth settings. If you ran `doorkeeper:install` solely for this setup, review its generated initializer and routes so you don't configure Doorkeeper twice.

## Built-in tools

| Category | Tool | Purpose |
| --- | --- | --- |
| Products | `search_products` | Search by product name or variant SKU. |
| Products | `get_product` | Read product descriptions and supported attributes. |
| Products | `get_product_variants` | List variants, including the master variant. |
| Products | `create_product` | Create a draft product. |
| Products | `create_variant` | Create a non-master variant using existing option values. |
| Products | `create_option_value` | Create a value under an existing option type. |
| Products | `update_product` | Update the name, description, and metadata fields. |
| Pricing | `get_variant_prices` | Read prices with their currency and country context. |
| Pricing | `update_variant_price` | Update an existing price row. |
| Pricing | `bulk_update_variant_prices` | Update up to 100 prices by SKU. |
| Inventory | `get_inventory_levels` | Read stock counts and backorderability by location. |
| Inventory | `search_inventory` | Search stock levels by SKU or product name. |
| Orders | `search_orders` | Search by order number, state, or store ID. |
| Orders | `get_order` | Read totals, status, and up to 100 authorized line items. |
| Orders | `get_order_status` | Read order, payment, and shipment states. |

Your client discovers each tool's input schema. Paginated tools accept `after_id` and `limit`, with a default limit of 25 and maximum of 100. Pass `next_after_id` from a response as the next request's `after_id` until it is null. Order results exclude customer contact information by default.

Product creation requires a valid `shipping_category_id`, supplied with the call or through `config.default_shipping_category_id` in your initializer.

Variant creation requires `product_id` and `sku`. Optional inputs include `price`, `option_value_ids`, `track_inventory`, `weight`, `height`, `width`, `depth`, and `cost_price`. If omitted, price defaults to the master price; stock items follow Solidus callbacks. Option values must belong to option types already attached to the product, with at most one value per option type.

Option value creation requires `option_type_id`, `name`, and `presentation`. It returns an `option_value_id` usable with `create_variant`; it does not attach an option type to a product. Both creation tools require their own connection permission and `mcp:write` consent, along with the corresponding Solidus permissions. Existing connections must explicitly enable these new permissions.

When upgrading from host-defined `CreateVariant` or `CreateOptionValue` tools with the same tool names, remove those entries from `config.custom_tools` to avoid duplicate registration.

Price updates require an existing price row, an explicit currency, and `country_iso` (`null` for general-country pricing). Supply decimal amounts as strings, such as `"19.95"`. Bulk updates report success or failure for each entry and can partially succeed. Review the results and retry only failed entries as appropriate.

The built-in price update tools use Solidus's standard pricing options. Stores with a custom `pricing_options_class` need a store-specific pricing tool.

Product and price updates take effect immediately. There are currently no built-in order or inventory mutation tools. Add your own, as desired.

## Custom serializers

You can change the product and order fields returned by the built-in tools without replacing those tools. Configure a serializer class in your initializer:

```ruby
config.product_serializer = 'Mcp::ProductSerializer'
# config.order_serializer = 'Mcp::OrderSerializer'
```

Both settings are optional. Leave one unset to keep that record's default representation. Use class-name strings so Rails can reload your serializers in development.

Each class implements `.call(record, context:)` and returns a JSON-compatible Ruby hash. For example, in `app/serializers/mcp/product_serializer.rb`:

```ruby
module Mcp
  class ProductSerializer
    def self.call(product, context:)
      {
        id: product.id,
        name: product.name,
        display_name: "#{product.name} (#{product.slug})"
      }
    end
  end
end
```

The returned hash replaces the default fields; it isn't merged with them. You choose which fields to include. The same interface works for orders.

| Setting | Used by |
| --- | --- |
| `product_serializer` | `search_products` and `get_product` |
| `order_serializer` | `search_orders` and `get_order` |

Pagination stays under the tool's control. `get_order` still adds its authorized, bounded line items and truncation indicator, so order serializers cannot return `line_items` or `line_items_truncated`. Variants, prices, inventory, order status, and write responses keep their existing representations.

### Using Alba or another library

The hook accepts plain Ruby classes or adapters for your preferred serialization library. Add that library to your app's Gemfile; it is not a runtime dependency of Solidus MCP.

For Alba, define `app/serializers/mcp/product_resource.rb`:

```ruby
module Mcp
  class ProductResource
    include Alba::Resource

    attributes :id, :name, :slug
  end
end
```

Then use this adapter in `app/serializers/mcp/product_serializer.rb`:

```ruby
module Mcp
  class ProductSerializer
    def self.call(product, context:)
      ProductResource.new(product, params: {policy: context}).to_h
    end
  end
end
```

Return a hash, not an encoded JSON string. For another library, adapt its output to the same interface.

### Authorization and field access

The gem checks that the connected user can read the product or order before calling your serializer. If you include information from related records, your serializer must check access to those records as well. For example, a store may allow someone to read an order's totals while restricting access to its shipping address.

For optional information, use `context.can?` to check access and omit the fields when the record is missing or access is denied:

```ruby
def self.call(order, context:)
  result = {number: order.number}
  address = order.ship_address
  result[:shipping_city] = address.city if context.can?(:read, address)
  result
end
```

The order still comes back if the shipping address is inaccessible; it simply has no `shipping_city` field. Clients should not assume an omitted field means no related record exists. The check uses the store's existing Solidus abilities and returns `false` for a missing record.

This does not create a separate MCP permission for addresses. An account with broad Solidus access will pass these record checks. Your store controls which fields its serializers expose.

If a related record is essential to the response, use `context.authorize_record!(:read, record)` instead. It raises an access-denied error and fails the call when the record is missing or access is denied. Access to the primary product or order is always required.

For related collections, use `context.scope(Model)` to return only records the connected user can read. These helpers do not automatically restrict the queries or associations you access elsewhere in the serializer.

These hooks do not add field-level permissions. Serializer changes apply to existing connections with access to the affected tools. To expose sensitive information under a separate grant, use a custom tool with its own permission key. Serializers are trusted application code, just like custom tools.

## Custom tools

To create your own custom MCP tools, add a named subclass of `SolidusMcp::Tool` under `app/tools`. For example, `app/tools/count_products.rb`:

```ruby
class CountProducts < SolidusMcp::Tool
  tool_name :count_products
  description 'Count products visible to the connected user.'
  category 'Products'
  permission 'count_products'
  read_only true
  ability :read, 'Spree::Product'

  protected

  def call
    { count: policy.scope(Spree::Product).count }
  end
end
```

Register its class name in your initializer:

```ruby
config.custom_tools = ['CountProducts']
```

Built-in tools are registered automatically. Use class-name strings for custom tools so Rails can reload them in development. Each tool needs a unique tool name and permission key. The new tool appears in the permission table, but it still needs an explicit grant before a client can use it.

### Tool declarations

These declarations form the gem's Ruby DSL for describing tools:

| Declaration | Required? | Purpose |
| --- | --- | --- |
| `tool_name :count_products` | Yes | Name exposed to MCP clients. Must be unique, start with a lowercase letter, and contain only lowercase letters, numbers, and underscores. |
| `description 'Count visible products.'` | Yes | Explains what the tool does to the connected agent. |
| `category 'Products'` | Yes | Groups the tool in the permissions interface. |
| `permission 'count_products'` | Yes | Unique key used for permission grants. Accepts the same characters as tool names, plus periods. |
| `read_only true` | Yes | Use `true` for read tools requiring `mcp:read`, or `false` for write tools requiring `mcp:write`. This declaration does not itself prevent database writes. |
| `ability :read, 'Spree::Product'` | At least one | Required Solidus ability. Repeat for additional abilities; all must pass. |
| `input :query, type: 'string', required: true` | No | Declares an argument and its JSON Schema constraints. Repeat for each argument the tool accepts. |

Declarations can be inherited from a parent tool class. Every tool also needs a protected `call` method containing its implementation.

Inputs are optional unless you specify `required: true`. Other options describe the accepted value, such as `type`, `enum`, `minLength`, or `minimum`:

```ruby
input :query, type: 'string', minLength: 1, required: true
input :limit, type: 'integer', minimum: 1, maximum: 100
```

Receive the arguments as keyword arguments in `call`, and put any defaults there:

```ruby
protected

def call(query:, limit: 25)
  # Your implementation here.
end
```

Undeclared arguments are rejected. Use `policy.scope(Model, action)` for collections and `policy.authorize_record!(action, record)` for individual records. Serialize only the fields the client needs. For writes, preserve your store's validations and business rules and recheck authorization before committing changes. The [built-in tools](app/tools/solidus_mcp/tools) provide examples.

If you call a tool from elsewhere in your Ruby app, such as a service, job, or another tool, use `.execute` with an authenticated MCP credential:

```ruby
CountProducts.execute(credential: credential)
```

This runs the same connection permission, OAuth scope, Solidus ability, and input checks used for MCP requests. MCP clients already go through these checks automatically.

Inside the tool, your implementation is still responsible for record access and business rules. For example, `policy.scope(Spree::Product)` limits a query to products the connected user can access; `Spree::Product.all` does not. Declaring abilities does not automatically restrict queries or enforce your store's rules.

### Changing existing tools

Connection grants are stored by permission key. If you expand what a tool can access or change—for example, adding inventory adjustments to a tool that only reads stock levels—give it a new permission key. This requires administrators to explicitly approve the expanded access.

For the same reason, don't assign a removed tool's permission key to a different tool. Existing connections may still hold that grant.

## Troubleshooting

| Problem | Check |
| --- | --- |
| Missing environment variable at startup | Confirm your launcher loads the variables. A `.env` file alone is not enough. |
| Discovery returns 404 | Check that the routes are loaded and appear before storefront or catch-all routes. |
| `unknown attribute 'resource' for Doorkeeper::AccessGrant`, missing PKCE columns, or missing administrator tables | Run `bin/rails solidus_mcp:migrate`, then restart the app to reload its schema. |
| MCP endpoint returns 401 | Complete the client's OAuth flow. A browser login alone does not provide an MCP token. |
| MCP endpoint returns 403 | Check the request's `Origin` against `allowed_origins`, and check whether the connection is disabled or its permission set was deleted. |
| Connected, but no tools appear | Check tool grants, token scopes, and Solidus abilities, then refresh the client's tool list. |
| A write tool is denied | Confirm both the tool grant and `mcp:write` consent. Reauthorize for additional scopes. |
| No superadministrator access | Verify the configured login email and Solidus admin status. Restart the whole process after changing the environment. |
| Own connection is read-only or administrator management is missing | Check your MCP administration level. Ordinary Solidus admin status does not grant MCP management rights. |
| Port already in use | Check which process owns it. Rails and the local end of an SSH tunnel need separate listeners on their respective machines. |
| HTTP URL rejected | HTTP endpoints are limited to loopback development and test use. HTTP OAuth callbacks require a literal loopback address. |

## Deployment and upgrades

Keep the gem revision and dependencies locked. During deployment, run host migrations followed by engine migrations, rebuild the app and its assets as needed, and restart the application processes. Use a shared Rails cache store so dynamic client registration rate limits apply across processes.

When adopting the administration hierarchy, configure at least one superadministrator and deliberately assign any MCP administrators. Existing Solidus roles do not automatically confer MCP administration rights. Existing tokens and connection grants are retained.

Review the [changelog](CHANGELOG.md) before upgrading and test the integration in your own store. Keep migrations compatible with the previous release where possible; application rollback should not automatically run down migrations.

## Local development and contributing

Run the checks with a disposable PostgreSQL database:

```sh
docker compose run --rm test
```

Or, with Ruby and a disposable `DATABASE_URL` configured locally:

```sh
RAILS_ENV=test bin/ci
```

The suite uses a fixture app; you don't need a separate store checkout or production credentials. See [CONTRIBUTING.md](CONTRIBUTING.md) for checks and release procedures.

## License

[BSD 3-Clause](LICENSE).
