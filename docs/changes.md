# Changes

Changes are proposals produced when MAIA or an enabled tool wants to modify workspace files or perform an operation requiring review. A change may contain a patch, shell commands, or another action. Related entries are grouped into a change set and may be inspected before execution.

Patch changes are applied to, or reverted from, the workspace with the change commands. Shell and action changes are run explicitly; their output and exit status are retained so the result can be inspected. Changes have states such as pending, applied, skipped, running, finished, and failed.

History may optionally be updated when a complete change set is applied or skipped. New files may also be added to the session's active filesets when the corresponding configuration permits it.

The command help is the authoritative reference for selecting, inspecting, applying, running, marking, saving, and deleting changes:

```bash
maia change --help
```

A typical review flow is:

```bash
maia change list --pending
maia change show <id>
maia change apply --dry-run <id>
maia change apply <id>
```
