# Hooks

Hooks are used to extend or customize MAIA's behavior without modifying the core functionality.
They are triggered before and after an action is performed.

Hooks use the following naming convention:

```text
<pre/post>-<type>-<action>
```

* `pre` means that the trigger happens before the action.
* `post` means that the trigger happens after the action.
* Both `pre` and `post` hooks are always available and receive the same arguments by default.
* `<type>` is the type of change: session, file, change, ...

In the list below pre- and post- prefix is omitted to save space.

| Hook   | Arguments    | Description |
| ---    | ---          | --- |
| change-delete | Change json file(s) | |
| change-state-applied | Change json file(s) | |
| change-state-pending | Change json file(s) | |
| change-state-skipped | Change json file(s) | |
| change-state-finished | Change json file | |
| change-state-failed | Change json file | |
| change-state-running | Change json file | |
| ---    | ---          | --- |
| file-context-update | | |
| ---    | ---          | --- |
| session-create | Session name | |
| session-delete | Session name(s) | |
| session-update | Session name | |
