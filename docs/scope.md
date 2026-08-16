# Scope

MAIA uses a layered configuration and data management model called **Scopes** to organize settings, snippets, system prompts, and other resources.

Each scope corresponds to a level of specificity and persists in distinct directories or files. This layered approach allows flexible customization and inheritance of configurations and resources.

## Scope Levels (From Most Specific to Least Specific)

- **Session**
  The most specific scope, tied to the current conversational session. Session scope stores history, outbox, system prompts, and snippets that apply only to that session.

- **Workspace**
  Represents the current project or workspace. Workspace scope holds project-level configuration, filesets, and shared snippets or prompts that apply to all sessions within the workspace.

- **Home**
  The local MAIA home directory, usually located at `.maia` under your current working directory or a configured path. Home scope contains user-specific configuration and snippets that override system defaults but are less specific than workspace or session settings.

- **User**
  The user’s global configuration directory, typically `~/.maia` or a user-defined path. User scope settings apply across all workspaces and sessions on the machine for the user.

- **System**
  The system-wide configuration, usually under `/etc/maia`. This scope is read-only and provides default system-level settings and snippets.

- **Default**
  Built-in defaults hardcoded within the tool itself. This is the fallback for any configuration or resource not defined in higher scopes.

## How Scopes Work

When the tool reads configuration or resources, it merges values from these scopes in order of specificity: session overrides workspace, which overrides home, and so forth. This ensures that more specific settings take precedence.

When writing configuration or snippets, the tool allows targeting a specific scope or uses sensible defaults (e.g., writing to the home scope for user configuration).

This scope hierarchy enables:

- Project- and session-specific customization without affecting global settings.
- Global defaults for consistency across projects.
- Easy overrides for experiments or temporary changes in a session.

## Examples of Use

- Editing the system prompt for a single session without affecting other sessions or workspaces.
- Defining a fileset in the workspace scope that is shared by all sessions.
- Setting an API key or global preference in the user or home scope.
- Providing default snippets in the system scope that can be overridden in user or session scopes.

---

**Tip:** You can explicitly specify the scope when managing configuration, snippets, or prompts using the `--scope` option in commands.

---
