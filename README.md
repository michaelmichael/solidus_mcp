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
gem 'solidus_mcp', '0.2.0.rc3'
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

The first command runs your app's migrations, including the generated Doorkeeper migration. The second runs the gem's migrations directly from the installed gem. These add connection permissions and audits, OAuth resource and PKCE attributes, MCP administrator assignments, durable stock-adjustment request records, and tool request records for image uploads and external workflows.

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

### MCP activity history

Open **AI connections → MCP activity** to review MCP actions. The history groups
read, create, update, and delete actions and filters by user email or ID, tool,
outcome, and a precise time range. Times without an explicit offset use the Rails
application time zone, which is displayed on the filters. Results use bounded
cursor pagination, with 50 events per page.

Every tool invocation is audited centrally, including custom tools and direct
Ruby `.execute` calls. SDK calls also record discovery and initialization, input
validation failures, and attempts to call unavailable tools. HTTP scope challenges,
disabled connections, and revoked known credentials are recorded even when they
are rejected before SDK dispatch. Requests with no identifiable credential remain
HTTP authentication failures; anonymous traffic is not written to this table.

Each event retains the user ID and MCP role at the time, OAuth application/client
and token IDs (not tokens), tool name and permission, action type, start/finish
times, duration, request/event IDs, outcome, and exception class. Safe numeric
input targets and returned record IDs are retained, including newly created
records. Requested update field names are recorded only when declared in the
tool's schema. Batch responses retain bounded record references and success flags,
so partial failures appear as **Partially succeeded**, not a successful whole batch.
Raw arguments, search text, values, response content, image data, credentials,
customer contact fields, and exception messages are not copied into the history.

MCP users see their own events. MCP administrators see their own events and
ordinary users' activity; other privileged users' history is hidden. Role snapshots
also protect historical privileged activity after an account is demoted or deleted.
Superadministrators see all activity, including attribution by ID after a user or
OAuth client is removed. The Admin history is read-only: it has no edit or delete
endpoints, and persisted model events reject normal edits/deletion. A started event
can be completed once through the recorder. Database administrators and trusted
application code still control the underlying database; this is not a tamper-proof
external audit archive.

The initial event must be saved before a tool runs. If that write fails, the tool
is not executed. Interrupted calls and completion-log failures remain
**Unfinished**, which can mean in progress or interrupted, not necessarily failed.
A completion-log failure is reported to the Rails logger without turning an
already-completed action into a failed response. The recorder does not wrap the
tool in a new transaction: ordinary tool transaction rollbacks preserve the event,
and gateway claim commits still work. If trusted Ruby callers enclose `.execute`
in their own transaction, audit rows participate in that enclosing transaction.

Run `bin/rails solidus_mcp:migrate` before using MCP after this upgrade. Keep the
activity tables available while serving MCP. Set a retention/archive policy in
trusted store maintenance code according to your volume and privacy requirements;
this extension does not automatically purge history. Invocation history records
who attempted or performed an MCP operation; it is separate from full model
versioning and before/after field diffs across every Solidus admin/API/CLI action.

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
| Products | `list_shipping_categories` | Discover shipping category IDs for product creation. |
| Products | `list_option_types` | Discover option types, optionally by name or product. |
| Products | `list_option_values` | Discover values for an authorized option type. |
| Products | `list_taxons` | Browse or search category IDs and hierarchy metadata. |
| Products | `add_product_to_taxon` | Add a category while preserving existing classifications and ordering. |
| Products | `list_product_images` | Read image metadata and display positions for a product or variant. |
| Products | `attach_product_image` | Upload a bounded base64 image with duplicate-request protection. |
| Products | `reorder_product_images` | Atomically set a parent's complete image order. |
| Products | `remove_product_image` | Permanently remove an image from its explicit parent. |
| Products | `publish_product` | Make a product available now, preserving discontinuation rules. |
| Products | `unpublish_product` | Withdraw availability while retaining variants and order history. |
| Products | `add_product_option_type` | Attach an existing option type without replacing other associations. |
| Products | `create_product` | Create a draft product. |
| Products | `update_product` | Update the name, description, and metadata fields. |
| Products | `update_variant` | Update SKU, weight, dimensions, cost price, or inventory tracking. |
| Pricing | `create_variant_price` | Create a price in an explicit currency/country context. |
| Pricing | `get_variant_prices` | Read prices with their currency and country context. |
| Pricing | `update_variant_price` | Update an existing price row. |
| Pricing | `bulk_update_variant_prices` | Update up to 100 prices by SKU. |
| Inventory | `list_stock_locations` | Discover warehouse IDs, names, and operational flags. |
| Inventory | `get_inventory_levels` | Read stock counts and backorderability by location. |
| Inventory | `search_inventory` | Search stock levels by SKU or product name. |
| Inventory | `adjust_stock` | Apply a signed stock movement with a reason and duplicate-request protection. |
| Orders | `search_orders` | Search by order number, state, or store ID. |
| Orders | `get_order` | Read totals, status, and up to 100 authorized line items. |
| Orders | `get_order_status` | Read order, payment, and shipment states. |
| Orders | `cancel_order` | Cancel a completed order through Solidus payment and inventory workflows. |
| Orders | `ship_shipment` | Fulfill one ready shipment with explicit tracking and notification choices. |
| Orders | `refund_payment` | Refund an explicit payment amount with durable retry protection. |

Your client discovers each tool's input schema. Paginated tools accept `after_id` and `limit`, with a default limit of 25 and maximum of 100. Pass `next_after_id` from a response as the next request's `after_id` until it is null. Order results exclude customer contact information by default.

Use `list_shipping_categories` to find a `shipping_category_id`, or configure
`default_shipping_category_id` for product creation. Use `list_option_types`
with an optional `query` (case-insensitive literal name/presentation search) or
`product_id` to discover option types. Pass an `option_type_id` to
`list_option_values` to discover its value IDs and presentations for variant
workflows. These read tools use separate grants and the standard cursor pagination.

Use `list_taxons` to discover category IDs. Each item contains `id`, `name`,
`parent_id`, `taxonomy_id`, and `depth`; roots have a null parent and depth zero.
The tool requires its own connection grant, `mcp:read`, and Solidus taxon read
access. It returns only authorized taxons, without expanding ancestors,
descendants, products, or taxonomy names.

Omit `parent_id` to browse all authorized taxons, pass `parent_id: null` to list
roots, or pass a positive parent ID to list direct children. Add `taxonomy_id`
to restrict results to an authorized taxonomy, and `query` for a case-insensitive
literal substring search on taxon names. Explicit parent and taxonomy IDs must
exist and be readable. Filters combine; a parent outside the selected taxonomy
returns an empty page. Results use the standard `after_id`/`limit` cursor in ID
order, which may differ from category display order. Keep the same filters while
following `next_after_id`. Matching names in different branches are distinguished
by their parent and taxonomy IDs; no recursive tree response is returned.

Call `add_product_to_taxon` with `product_id` and a `taxon_id` discovered through
`list_taxons`. It requires its own connection grant, `mcp:write`, product update
access (including the `taxon_ids` attribute), taxon read access, and permission to
create the classification. New classifications append to the target taxon's
product ordering through Solidus's normal model workflow. Existing category
assignments, their positions, and variants are preserved. Repeating a successful
call returns `attached: true` without adding a duplicate or moving the product.
Calls through this tool lock the product and target taxon before checking for an
existing classification; custom classification writers should use the same lock
order to coordinate changes. The tool does not create taxons or replace the
product's full category list.

To attach an existing option type, call `add_product_option_type` with
`product_id` and `option_type_id`. It requires its own connection grant,
`mcp:write` consent, product update access, option-type read access, and permission
to create the product/option-type association. It preserves existing option types,
their positions, and variants. Repeating a successful call returns `attached: true`
without adding a duplicate. Calls through this tool lock the product to serialize
concurrent attachments; custom association writers should use the same lock.
Attaching a type does not create option values or variants.

Product creation requires a valid `shipping_category_id`, supplied with the call or through `config.default_shipping_category_id` in your initializer.

Price updates require an existing price row, an explicit currency, and `country_iso` (`null` for general-country pricing). Supply decimal amounts as strings, such as `"19.95"`. Bulk updates report success or failure for each entry and can partially succeed. Review the results and retry only failed entries as appropriate.

The built-in price update tools use Solidus's standard pricing options. Stores with a custom `pricing_options_class` need a store-specific pricing tool.

`update_variant` accepts a `variant_id` and a nonempty `changes` object containing
only `sku`, `weight`, `height`, `width`, `depth`, `cost_price`, or `track_inventory`.
It works for master and ordinary variants. Supply weight, dimensions, and cost
price as nonnegative decimal strings with at most two decimal places, for example
`{"weight": "1.25", "cost_price": "7.99", "track_inventory": false}`. Weight and
dimensions support up to `999999.99`; cost price supports up to `99999999.99`.
Omitted fields retain their values; nulls and empty updates are rejected. Cost
price uses the variant's cost currency under Solidus's normal validation and
callback behavior. Currency changes are outside this tool's supported fields.
The tool requires its own grant, `mcp:write`, product and variant update abilities,
and access to every changed variant attribute. Changes save atomically under a
variant lock and preserve Solidus validations. Inventory tracking controls whether
Solidus tracks availability; it does not adjust stock quantities. Selling prices
continue to use the pricing tools.

`list_stock_locations` returns authorized locations, including inactive ones,
with IDs, names, and `active`, `default`, `fulfillable`, `backorderable_default`,
`propagate_all_variants`, and `restock_inventory` flags. It uses the standard
cursor pagination and requires its own grant and `mcp:read` consent. Location IDs
match `stock_location_id` in existing inventory reads and identify the location
for `adjust_stock`. Address and contact fields are omitted.

`adjust_stock` requires `variant_id`, `stock_location_id`, a nonzero signed integer
`quantity`, a nonblank `reason` (up to 1,000 characters), and an `idempotency_key`.
For example:

```json
{
  "variant_id": 42,
  "stock_location_id": 3,
  "quantity": 5,
  "reason": "Cycle count correction",
  "idempotency_key": "cycle-count-2026-11-12-42-3"
}
```

Run `bin/rails solidus_mcp:migrate` before using this tool after upgrading. It
requires its own connection grant, `mcp:write` consent, read access to the product,
variant, and location, update access to the stock item and its `count_on_hand`
attribute, and permission to create the stock movement. The variant/location
stock item must already exist; the tool never creates one. Inventory tracking
must be enabled for both the variant and store, and the location must be active
for a new adjustment. Quantities range from -2147483647 to 2147483647; the resulting
stock count must fit a signed 32-bit integer.

Positive quantities increase stock; negative quantities decrease it. The tool
creates a standard Solidus stock movement, preserving validations and backorder
processing. Negative balances are permitted only for backorderable stock items.
Positive movements may fill outstanding backorders through Solidus callbacks.
The supplied reason is retained in the movement's `SolidusMcp::StockAdjustment`
originator, together with the connection identity and saved response.

Choose a new key for each intended adjustment. Keys are case-sensitive, up to
128 characters, and accept letters, digits, underscores, periods, colons, and
hyphens. Keys are scoped to the connection (OAuth application and user), so they
survive token refresh. Retry uncertain or successful requests with the **same key
and identical inputs**. The movement, count changes, request record, and original
response commit in one database transaction. Duplicate concurrent requests apply
once; different keys serialize against the stock item. Reusing a completed key
with different inputs fails. Failed transactions leave no request record and can
be retried. Custom database writers and nontransactional side effects in
store-specific callbacks remain the host application's responsibility.

A successful retry checks current grants and record access and returns the
original movement ID and before/after counts, even if stock later changes or the
location/tracking flags are disabled. It does not apply another movement. The
counts describe that adjustment, not a fresh inventory read. Keep the stock
adjustment records: deleting them removes duplicate-request protection for their
keys. No automatic expiry or pruning is performed.

Product and price updates take effect immediately.

### Product images and availability

All four image tools require `product_id`. Omitting `variant_id` selects the
product's master variant, matching Solidus's product image association. An explicit
`variant_id` must belong to that product. Sibling variants' images are separate.
Read calls require product, variant, and image read access. Image writes require
product and variant update access plus the appropriate image create, update, or
destroy ability. Each tool has its own connection grant and OAuth scope.

`list_product_images` uses ID cursor pagination and returns image IDs, parent IDs,
positions, alt text, and ActiveStorage content type/byte size. Positions describe
display order; no signed URLs, storage keys, credentials, or internal paths are
returned.

`attach_product_image` accepts `filename`, `content_type`, `data_base64`, an optional
`alt`, and `idempotency_key`, in addition to the parent IDs. Supported MIME types
are `image/png`, `image/jpeg`, `image/gif`, and `image/webp`, subject to the store's
Solidus image validations. Input must be strict base64, at most 512 KiB decoded,
with matching detected content type and a plain filename. Remote URLs are not
accepted. This upload tool supports the standard ActiveStorage adapter; stores
using a custom attachment adapter need a store-specific upload tool. Uploads
append to the parent's image list. Use the same key and identical file/metadata
for retries; changing inputs for a completed key fails. Keys use the stock tool's
character and length rules and are scoped by connection and tool. Database
failures roll back image and request records and delete the uploaded object;
cleanup failures are logged for inspection. As with ordinary ActiveStorage
uploads, process termination can leave unattached storage objects for store
maintenance to remove. Successful request records must be retained for retries.

`reorder_product_images` accepts the complete `image_ids` array for one parent,
with at most 100 IDs. Each ID must appear exactly once and be authorized for
position updates. Partial, foreign, duplicate, and unauthorized lists fail
atomically. An empty array is valid only for an empty parent. Repeating the same
order preserves the result. Image writers through these tools lock product then
variant; custom image writers should coordinate with the same lock order.

`remove_product_image` requires `image_id` and its parent context. It permanently
destroys the image through Solidus callbacks. Standard ActiveStorage attachment
cleanup may enqueue a purge job; run the store's job workers to remove stored
files. Missing, foreign, or already removed IDs fail without deleting another
image. Retrying deletion is safe, but returns an unavailable-record error once
it has succeeded.

`publish_product` and `unpublish_product` each accept `product_id` and require
separate write grants, product update access, and `available_on` attribute access.
Publishing sets `available_on` to now if necessary. It refuses already discontinued
products and preserves any future `discontinue_on` date. Unpublishing sets
`available_on` to null, preserving discontinuation, variants, and order history.
Both preserve Solidus validations and are safe to repeat. Publishing changes
availability, not stock, price, taxon assignment, or store-specific visibility rules.

### Creating price contexts

`create_variant_price` requires `variant_id`, `currency`, explicit nullable
`country_iso`, and nonnegative decimal-string `amount` with at most two decimal
places (maximum `99999999.99`). It needs its own write grant, product and variant
update access, and authorization to create the new price. Country-specific prices
must reference a valid country. Only the standard Solidus `pricing_options_class`
is supported.

Calls lock the variant and check all active rows in the exact currency/country
context. No existing row means a new validated price is created. One existing
row with the same amount is returned on retry only when it is readable. Conflicting
amounts and ambiguous duplicate contexts fail; use the update tools to change
existing amounts. Custom price creators should use the same variant lock to
coordinate context creation. The tool does not modify existing or discarded rows.

### Cancellation, shipping, and refunds

Run `bin/rails solidus_mcp:migrate` after upgrading before using upload or external
workflow tools. All three external workflow tools require their own write grant,
`mcp:write`, a connection-scoped `idempotency_key`, and record authorization for
the affected workflow. Keys follow the same character/length rules as stock
adjustments and are scoped by connection and tool; retain their request records.
They must run outside any caller-managed database transaction so their durable
claims commit before gateway, notification, or fulfillment callbacks run.

`cancel_order` requires `order_id` and a nonblank `reason` (up to 1,000 characters).
Only completed, Solidus-cancellable orders whose shipments are all pending or
ready may be newly canceled. Already canceled orders return their canceled state.
The tool uses `canceled_by`, preserving Solidus restocking, payment void/refund,
callbacks, actor attribution, and canceled timestamps. The supplied reason is
retained in the request audit; Solidus's payment canceller keeps its standard
refund-reason behavior. Authorization includes the order cancel action, affected
shipments, payments and potential refunds/reasons, stock items/movements, variants,
products, locations, and inventory units affected by restocking/backorders. It
never forces an arbitrary state or cancels already shipped fulfillment.

`ship_shipment` requires `shipment_id` and explicit boolean `notify_customer`;
`tracking` is optional and, when supplied, requires tracking attribute update
access. New fulfillment requires a ready shipment on a completed order, with
on-hand units and no unresolved backorders. The tool calls Solidus's shipment
shipping event, creating a carton and shipping its eligible inventory units.
It fulfills the selected shipment while Solidus recalculates the order's overall
state. It does not decrement stock again; reservation happened in the normal
order workflow. Permissions cover the order, shipment, inventory units, variants,
products, shipping address/method, location, and prospective carton. Notifications
use the standard Solidus subscriber and are suppressed when `notify_customer` is
false. Already shipped shipments do not create another carton; conflicting new
tracking is rejected. Store-specific subscribers retain their usual behavior.

`refund_payment` requires `payment_id`, `refund_reason_id`, `currency`, and a
positive decimal-string `amount` with at most two decimal places. Currency must
match the payment, and the amount must be exactly representable in that currency's
minor units. The tool supports partial refunds, completed payments only, and
amounts no greater than remaining credit. It locks order then payment and uses
Solidus's refund validation and `perform!` workflow. It requires order/payment
update access, refund-reason read access, and authorization for the new refund.
Responses contain refund/payment IDs, amount, currency, and success, excluding
gateway authorization codes, source data, customer contact details, and raw
provider responses. Solidus retains its normal refund logs and reason records.

Each external workflow commits a `SolidusMcp::ToolRequest` claim before starting.
Successful calls save their original result and return it on identical retries,
checking current access first. Changing inputs under the same key fails. An
order-wide database guard prevents overlapping external operations, including
calls made through different connections. Failures before effects begin mark the
request `failed` and can be retried. Once a callback or gateway call might have
run, failure marks the request `uncertain`. A process crash can leave it
`processing`. Both states block further external workflow calls for that order,
including new keys: they never automatically reissue a potentially completed
refund, void, notification, or fulfillment operation.

For reconciliation, a trusted operator must inspect the request ID, payload,
connection, timestamps, Solidus records, gateway logs, and actual fulfillment or
notification outcome. Preserve that audit and correct any database state to match
the verified external result before resolving the request through trusted
application code. A confirmed success needs a `succeeded` status and original
result; `failed` is appropriate only after confirming no external effect occurred.
Do not delete a request or change its status merely to bypass the guard. These
protections coordinate MCP tools; custom integrations and manual gateway actions
must be reconciled separately.

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
| `audit_action "create"` | No | Classify writes as `create`, `update`, or `delete` in activity history. Read tools default to `read`; other writes default to `update`. Must agree with `read_only`. |
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
