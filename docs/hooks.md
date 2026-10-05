# Hooks

Hooks are used to extend or customize MAIA's behavior without modifying the core functionality.
They are triggered before and after an action is performed.

Hooks use the following naming convention:

```text
<pre/post/other>-<type>-<action>
```

* `pre` means that the trigger happens before the action.
* `post` means that the trigger happens after the action.
* `other` means a hook of some other type (for example: during)
* Both `pre` and `post` hooks are always available and receive the same arguments by default.
* `<type>` is the type of change: session, file, change, ...

In the list below pre- and post- prefix is omitted to save space.

| Hook   | Arguments    | Description |
| ---    | ---          | --- |
| file-write | Path | |
| ---    | ---          | --- |
| change-create | ID | There is no `pre-` hook. |
| change-delete | Change json file(s) | |
| change-state-applied | Change json file(s) | |
| change-state-pending | Change json file(s) | |
| change-state-skipped | Change json file(s) | |
| change-state-finished | Change json file | |
| change-state-failed | Change json file | |
| change-state-running | Change json file | |
| ---    | ---          | --- |
| file-context-update | | There is no `pre-` hook. |
| ---    | ---          | --- |
| session-create | Session name | |
| session-delete | Session name(s) | |
| session-update | Session name | |
| ---    | ---          | --- |
| job-start | ID, tool, tool args | |
| job-cancel | ID | |
| job-delete | ID | |
| job-finish | ID | There is no `pre-` hook. |
| ---    | ---          | --- |
| send | API type | |
| send-loop | Iteration, Allowed iterations left, Messages json | |
| tool-calls | Pre: Tool temp dir, Tool calls; Post & During: Tool temp dir, Tool call IDs | There is a `during-` hook too. |
| tool-call-fork | Pre: Tool temp dir, ID, Status, tool name, tool args | For `pre` the status is always 0. |
| tool-call-finished | Tool temp dir, ID | There is no `pre-` hook. |

NOTE! The hooks may change in the future even at minor revision changes. If you want a hook to be
permanent, let the devloper know. The reason for this is that the hooks are not tested and it is therefore
impossible to judge whether the current ones are suitable.

