# Changelog

## 0.1.0 — unreleased

- Inline OAuth scope warnings in AI connections, including expired and mixed
  token cases, plus host-configurable reconnect instructions. Saving a store
  permission never changes token scopes.

- Optional `SolidusMcp::Tool` classes with co-located declarations and handlers,
  registered with `Registry#register`; legacy handler registration is unchanged.
- Policy-protected SDK tools exposed through `Server.tools` for incremental host
  migrations, with class-name resolution compatible with Rails reloading.

- Explicit resource, permission and MCP tool registry.
- Per-application/user grants, OAuth scope and Solidus ability checks.
- Permission-aware discovery and execution using the Ruby MCP SDK.
- Optional SolidusAdmin connection management with CSRF protection, stale-write
  detection and transactional permission-change history.
- Standalone Rails test application and CI for admin and core-only installations.
