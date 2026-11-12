# Changelog

## Unreleased

## 0.2.0.rc3 (2026-11-12)

- Add centralized MCP activity auditing for tool calls and protocol actions,
  including denied attempts, schema errors, partial batches, custom tools and
  direct Ruby execution. Retain actor/client attribution, safe target/result IDs,
  declared changed-field names, outcomes and timing without copying raw inputs,
  responses, credentials or exception messages. Require a saved initial event
  before execution and preserve unfinished evidence on interruption.
- Add a read-only **AI connections → MCP activity** browser with action grouping,
  user/tool/outcome/time filters and cursor pagination. Enforce the existing MCP
  hierarchy and retain historical role snapshots to protect privileged activity.
  Add optional custom-tool `audit_action` metadata. Run engine migrations before
  serving MCP after upgrading.

- Complete the pending standard tool catalog with separate tool and spec files:
  image listing, bounded base64 upload, complete reordering and removal; product
  publication/withdrawal; price-context creation; order cancellation, shipment
  fulfillment, and payment refunds. Preserve Solidus validations and workflows,
  parent/record and attribute permissions, ordering, and least-privilege grants.
- Add durable tool request records for image retries and external operations.
  Commit gateway/fulfillment claims before effects; retain uncertain outcomes and
  block further external operations on that order until trusted reconciliation.
  Run `bin/rails solidus_mcp:migrate` after upgrading. Add ActiveStorage tables only
  to the disposable test host and cover real attachment and carton workflows.

- Add `add_product_to_taxon` with a dedicated write grant, product/taxon and
  classification authorization, and additive, repeat-safe category assignment.
  Preserve existing classifications and append new products in Solidus's taxon
  ordering while holding product and taxon locks.

- Add `list_taxons` with a dedicated read grant, scoped cursor pagination, literal
  name search, taxonomy and direct-parent filters, and a roots-only null-parent
  filter. Return bounded hierarchy metadata and authorize explicit filter records.

- Add `adjust_stock` with a dedicated write grant, record and stock-count
  authorization, signed Solidus stock movements, reasons, and backorder handling.
  Add durable connection-scoped request keys with a unique index and atomic
  movement/result recording to prevent duplicate adjustments across retries and
  concurrent calls. Run `bin/rails solidus_mcp:migrate` after upgrading, and retain
  the request records to preserve duplicate-request protection.

- Add `update_variant` for SKU, dimensions, weight, cost price, and inventory
  tracking, with a dedicated write grant, attribute-aware authorization before
  and after assignment, decimal-string inputs, and validated atomic updates.
- Add scoped, paginated `list_stock_locations` with operational flags and a
  dedicated read grant, omitting location addresses and contact details.

- Add `add_product_option_type` with a dedicated write grant, authorization for
  both records and new associations, and additive, repeat-safe attachment under
  a product lock. Preserve existing option positions and variants.

- Add paginated `list_option_types`, `list_option_values`, and
  `list_shipping_categories` discovery tools with separate grants, scoped records,
  parent authorization, and literal option-type name filtering.

- Style the OAuth consent page with the MCP admin palette and shared controls,
  including responsive layout and keyboard focus indicators, without requiring
  Solidus Admin or changing the authorization flow.

- Express nullable country inputs in pricing tool schemas with `anyOf` branches
  for improved MCP client compatibility, preserving required fields and validation.
## 0.2.0.rc2 (2026-11-08)

- Add optional product and order serializer hooks for built-in read tools, with
  a plain Ruby interface and an Alba adapter example. Preserve record authorization,
  pagination, and tool-owned order line items; resolve class names across Rails reloads.
- Add `Policy#can?` so serializers can omit inaccessible optional related fields
  while retaining strict authorization for required records.

## 0.2.0.rc1 (2026-11-08)

First public release candidate. The earlier registry implementation was unpublished.

- Support Rails 7.2 and 8.0 on Ruby 3.2 or newer, with explicit Rails component
  dependencies and CI coverage for both Rails versions, with and without
  Solidus Admin. Use Rails 7.2-compatible migrations and registration rate limits.

- Add environment-designated MCP superadministrators and audited, gem-owned
  MCP-admin assignments. MCP admins manage ordinary users' grants; only
  superadministrators can assign admins or manage privileged connections.
  Solidus role checkboxes do not grant MCP-admin authority. Run the new engine
  migration and configure superadministrator login emails before deployment.
  Add an accessible account-search dropdown for assigning and restoring admins.
  See [MCP administration hierarchy](docs/administration.md).

- Add draft product creation with an overridable shipping-category default,
  record-level authorization, and structured MCP results.
- Isolate test caches so registration throttles do not leak between suite runs.

- Make the self-contained engine the canonical implementation; retire the
  unpublished host registry API and compatibility instructions.
- Offer explicit read/write access review on the consent screen for clients
  without scope controls, preserving registration limits and PKCE.

- Add audited permission-set deletion, a deleted-sets view and explicit restoration.
- Bundle scoped admin styles and permission tables with category and global
  selection controls, without requiring host Tailwind configuration. Preserve
  connection owners during theme changes and highlight AI connections in navigation.

- Replace resource/operation maps with an automatically registered catalog of
  thirteen built-in tools and additive custom tool classes.
- Add standard product, pricing, inventory-read and order-read implementations
  with explicit serializers and record authorization.
- Add per-entry bulk pricing using normal Solidus validation and row locks.
- Own the authenticated Streamable HTTP endpoint, OAuth metadata, registration
  and consent integration while retaining Doorkeeper token/PKCE handling.
- Use independent `mcp:read` / `mcp:write` scopes and unique default-deny tool
  permissions; support standard OAuth insufficient-scope challenges.
- Retain transactional permission auditing, optimistic locking and SolidusAdmin
  controls, grouped by tool category with scope diagnostics.
- Add direct gem migration task, real Solidus integration coverage and actual
  development/production loading checks.
- Breaking: remove resource declarations, legacy handler registration, scope
  implications, default grants and redundant capability-discovery tools. See
  README for installation and upgrade instructions.

## 0.1.0

Initial unpublished registry, connection permissions and admin integration.
