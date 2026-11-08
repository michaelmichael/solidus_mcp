# MCP administration hierarchy

MCP access requires a Solidus administrator account. MCP administration has three
levels, independent of the ordinary Solidus role checkboxes:

| Action | MCP user | MCP administrator | MCP superadministrator |
| --- | --- | --- | --- |
| Connect an OAuth client and use assigned tools | Yes | Yes | Yes |
| View own connections | Yes | Yes | Yes |
| Manage ordinary MCP users' connections | No | Yes | Yes |
| Manage their own or other privileged connections | No | No | Yes |
| Assign or remove MCP administrators | No | No | Yes |
| Change the superadministrator list in the store UI | No | No | No |

All existing OAuth scope limits, connection grants, and Solidus record abilities
still apply to tool calls. An administration role does not enable tools or expand
OAuth consent automatically.

## Designate superadministrators

Set the deployment environment variable to the intended accounts' login emails:

```dotenv
SOLIDUS_MCP_SUPERADMIN_EMAILS=owner@example.com,security@example.com
```

The gem reads this setting automatically when the application starts. No MCP
initializer setting is needed. Addresses are separated by commas; surrounding
whitespace and letter case are ignored. Invalid addresses fail configuration.
With no addresses configured, there are no superadministrators and nobody can
assign MCP administrators through the UI. The matching accounts must also be
Solidus administrators. Ambiguous, case-insensitive matches grant no authority.

Change the setting through deployment configuration, then restart the entire
application process so it receives the new environment. A local `.env` file is
suitable only when the launcher loads it; Rails does not load it automatically.

Trusted host configuration can alternatively set `config.superadmin_emails`
to an explicit array of login emails. This configuration must not be exposed as
an ordinary user-editable store setting.

Superadministrator access follows the configured login address. If an account's
email changes, update the deployment setting as well. Protect privileged email
changes and account reuse through host account-administration controls.

## Assign MCP administrators

1. Sign in as a configured MCP superadministrator.
2. Open **AI connections**, then **Manage MCP administrators**.
3. Search for a login email and choose an eligible account from the dropdown, then select **Assign MCP administrator**.
4. Use the assignment's controls to remove or restore MCP-admin authority.

The dropdown supports mouse and keyboard selection. It lists only eligible
Solidus administrators, excludes superadministrators and active MCP admins, and
lets you restore a previously removed assignment. Account IDs remain internal
association keys; there is no ID to look up or enter in the UI.

Assignments belong to the gem's `solidus_mcp_administrators` table. They are not
Solidus roles. Checking a Solidus role named `mcp_admin` has no effect on MCP
administration. There is no MCP tool for assigning administrative authority.

MCP administrators can grant, remove, disable, delete, and restore ordinary MCP
users' connection permission sets. Their own connections are read-only, and other
privileged accounts' connections are hidden. Superadministrators manage privileged
connections, including their own. This prevents an MCP administrator from granting
themselves broader tool access or changing another administrator's grants.

Assignment changes have actor-attributed audit records and optimistic locking.
Assignments and their audits commit together. Removing an assignment takes effect
on subsequent requests; it does not delete the person's existing tool grants.
Removing Solidus administrator status also prevents OAuth authorization and tool
use, regardless of an assignment or configured superadministrator email.

## Host authorization and account protection

Host Solidus abilities remain an additional restriction. Connection management
uses `:mcp_connections`; the assignment screen uses `:mcp_administrators`. The
engine enforces its hierarchy even when Solidus grants `manage :all`.

The hierarchy protects the engine's management actions and prevents elevation
through the Solidus role checkboxes. It does not replace host account security:
restrict who can change privileged accounts' passwords, email addresses, login
methods, or impersonate them. Someone who can take over a configured
superadministrator's account can act with that account's authority. Server and
database operators remain trusted.

For hosts without SolidusAdmin, trusted host code can call:

```ruby
assignment = SolidusMcp::Administrator.find_or_initialize_by(user: target_user)
assignment.change!(
  actor: superadmin_user,
  enabled: true,
  lock_version: assignment.persisted? ? assignment.lock_version : -1
)
```

Use `enabled: false` to revoke an existing assignment. The method enforces current
superadministrator status, host abilities, target eligibility, and version checks.
It cannot assign or revoke configured superadministrator status.

`ConnectionPolicy#change!` and `#delete_permissions!` also enforce the hierarchy,
including restrictions on privileged connection owners. Direct database writes
by trusted application code are outside these management APIs.

## Upgrading

Run the engine migrations before serving the new version:

```sh
bin/rails solidus_mcp:migrate
```

This creates administrator-assignment and role-audit tables. Configure at least
one superadministrator and restart the app, then deliberately assign any MCP
administrators. There is no automatic elevation from Solidus roles or existing
connection permissions. Existing tokens and tool grants are retained.

The earlier development setting `SOLIDUS_MCP_SUPERADMIN_USER_IDS` is no longer
used. Replace it with `SOLIDUS_MCP_SUPERADMIN_EMAILS` when upgrading from that
configuration. This identifier change needs no additional database migration.
