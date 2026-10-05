# Sessions

A session is MAIA's persistent conversational context. It has an outbox for pending user input, conversation history, and session-specific context selections. The active session is selected with `MAIA_SESSION` environment variable or by using the `maias` shell helper.

Sessions may use a workspace and a profile. These selections determine the project files and configuration context used when messages are prepared. A session may also select active filesets and additional filesets that are sent with requests.

## Session context

A session can have:

- a workspace;
- a profile;
- active filesets used by file operations and context display;
- extra-send filesets whose content is sent to the AI but is not modified by ordinary file or change operations;
- tools, skills, instructions, and tasks;
- outbox content waiting to be sent; and
- conversation history.

The values used for a new session come from the command-line options, a copied source session, or the relevant configuration defaults. See `maia session --help` for the precedence and fileset-resolution options.

## Creating and copying sessions

A new session starts with empty session conversation data. A session can also be created by copying an existing session. Copying preserves the conversational and context data selected by the source session, while logs and background jobs are not copied.

A session can be defunct when its directory exists but its session metadata is missing. Defunct sessions may contain history or outbox data and can be deleted, but they cannot be used normally until recreated.

## Viewing session context

The session commands can show the session metadata, the effective file content, the selected files, and the instructions or tasks currently provided to the AI. These views are useful for checking what a request will contain before sending it.

The exact command forms and output options are available from:

```bash
maia session --help
```

## Managing session history

Conversation history belongs to the session. It contains the messages sent to the AI and the responses received, including tool calls and tool results. History operations affect the active session unless another session is selected through the usual session-selection mechanisms.

Use `maia history` to inspect and manage it. With no subcommand, the most recent entry is shown. `show` can display a selected range and can filter the output to user, assistant, or tool entries. The `--raw` and `--json` options provide the underlying JSON representation, which can be useful for scripts or detailed inspection.

History ranges can refer to individual entries, inclusive ranges, open-ended ranges, `last`, `last-n`, `all`, or the whole history. The complete range syntax is described by:

```bash
maia history --help
```

### Compacting history

`maia history summarize` (also available as `compact`) asks the AI to summarize the conversation. The summary request is made without workspace files, tools, or skills. If successful, the older history entries are hidden from subsequent AI requests and marked as summarized; the most recent entries are retained. This reduces the amount of history included in later requests without deleting the original entries.

Compacting uses the configured summary prompt and can therefore be affected by the session's configuration and prompt context. Inspect the result with:

```bash
maia history show all
```

### Pruning history

`maia history prune` reduces the content of selected entries while retaining the entries themselves. By default it operates on assistant entries and uses the configured `prune_mode`. The role can be selected explicitly with `--assistant`, `--tool`, or `--user`.

Pruned entries retain a reference to their original text. `maia history restore` can restore entries that have a saved original. Pruning is useful when the history is too large, while still retaining its structure and an indication that content was removed. It is not the same as deleting history.

For other history operations and the exact command syntax, range behavior, role filters, and options, use:

```bash
maia history --help
```

## Session and scope

Session data is the most specific layer in MAIA's scope hierarchy. It normally overrides data from the selected profile, workspace, home, user, and system scopes. The session page describes the conversational role of the session; [scope](scope.md) describes the general inheritance model.
