# Changelog

## 0.2.0 (unreleased)

- Replace resource/operation maps with an automatically registered catalog of
  twelve built-in tools and additive custom tool classes.
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
  README for the one-time migration and immutable release workflow.

## 0.1.0

Initial unpublished registry, connection permissions and admin integration.
