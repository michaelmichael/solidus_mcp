# Changelog

## Unreleased

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
