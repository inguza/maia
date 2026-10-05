# Profiles

A profile is a reusable configuration context selected by a session. It can provide profile-specific tools, skills, instructions, tasks, and configuration-related resources without changing the session's own data.

Profiles may be nested. A nested profile is named using `%` components, for example `base%project`. The selected profile is recorded by the session.

Profiles are discovered through the normal MAIA search locations and may be restricted by the `allowed_profiles` configuration setting. Profile creation, listing, and deletion are described by:

```bash
maia profile --help
```
