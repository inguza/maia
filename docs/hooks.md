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
* Both `pre` and `post` hooks are typically available and receive the same arguments by default.
* `<type>` is the type of change: session, file, change, ...

In the list below pre- and post- prefix is omitted to save space.

| Hook | Arguments | Description |
| --- | --- | --- |
| `file-write` | Path | File-write event. |
| --- | --- | --- |
| `post-change-create` | ID | A change was created. |
| `pre-change-delete` | Change metadata file(s) | Before change artifacts are deleted. |
| `post-change-delete` | Change metadata file(s) | After change artifacts are deleted. |
| `pre-change-state-applied` | Change metadata file(s) | Before changes are marked applied. |
| `post-change-state-applied` | Change metadata file(s) | After changes are marked applied. |
| `pre-change-state-pending` | Change metadata file(s) | Before changes are marked pending. |
| `post-change-state-pending` | Change metadata file(s) | After changes are marked pending. |
| `pre-change-state-skipped` | Change metadata file(s) | Before changes are marked skipped. |
| `post-change-state-skipped` | Change metadata file(s) | After changes are marked skipped. |
| `pre-change-state-finished` | Change metadata file(s) | Before changes are marked finished. |
| `post-change-state-finished` | Change metadata file(s) | After changes are marked finished. |
| `pre-change-state-failed` | Change metadata file(s) | Before changes are marked failed. |
| `post-change-state-failed` | Change metadata file(s) | After changes are marked failed. |
| `pre-change-state-running` | Change metadata file(s) | Before changes are marked running. |
| `post-change-state-running` | Change metadata file(s) | After changes are marked running. |
| --- | --- | --- |
| `post-file-context-update` | — | File context changed. |
| --- | --- | --- |
| `pre-session-create` | Session name | Before a session is created. |
| `post-session-create` | Session name | After a session is created. |
| `pre-session-delete` | Session name | Before a session is deleted. |
| `post-session-delete` | Session name | After a session is deleted. |
| `pre-session-update` | Session name | Before session metadata is updated. |
| `post-session-update` | Session name | After session metadata is updated. |
| --- | --- | --- |
| `pre-job-start` | ID, tool, tool arguments | Before a background tool job starts. |
| `post-job-start` | ID, tool, tool arguments | After a background tool job starts. |
| `pre-job-cancel` | ID | Before a job is cancelled. |
| `post-job-cancel` | ID | After a job is cancelled. |
| `pre-job-delete` | ID | Before job data is deleted. |
| `post-job-delete` | ID | After job data is deleted. |
| `post-job-finish` | ID | A tool job finished. |
| --- | --- | --- |
| `pre-send` | API type | Before sending starts. |
| `post-send` | — | After sending and tool iterations finish. |
| `pre-send-request` | ID, API type, URL, payload file | Before an HTTP request is made. |
| `post-send-request` | ID, API type, URL, response | After an HTTP response is received. |
| `pre-send-loop` | Iteration, allowed iterations left, messages JSON | Before an API/tool iteration. |
| `post-send-loop` | Iteration, allowed iterations left, messages JSON | After an API/tool iteration. |
| --- | --- | --- |
| `pre-tool-calls` | Tool temporary directory, tool calls | Before the requested tools are forked. |
| `during-tool-calls` | Tool temporary directory, tool call IDs | After forking and before waiting for completion. |
| `post-tool-calls` | Tool temporary directory, tool call IDs | After all requested tools finish. |
| `pre-tool-call-fork` | Tool temporary directory, ID, status, tool name, tool arguments | Before one tool process is forked; status is 0. |
| `post-tool-call-fork` | Tool temporary directory, ID, status, tool name, tool arguments | After one tool process is forked or rejected. |
| `post-tool-call-finished` | Tool temporary directory, ID | After one tool finishes. |

NOTE! The hooks may change in the future even at minor revision changes. If you want a hook to be
permanent, let the devloper know. The reason for this is that the hooks are not tested and it is therefore
impossible to judge whether the current ones are suitable.

