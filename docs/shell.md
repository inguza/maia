# Shell

The `maia shell` provides a standard bash shell with additional functionality.

The following functionality is added:

* The prompt shows the active session, workspace and for monitored shells the shell name.
  An `!` is added if the session does not exist.
* The prompt shows the active workspace.
  An `!` is added if the workspace does not exist.
  An `§` is added if the current directory is outside the workspace root.
  An `-` is shown if there is no active workspace defined.
* For monitored shells, the prompt also shows the shell name.
* The `maias` command changes the active session.
* The `maiaforeachsession` function executes a command for each selected session.

## Prompt

A `maia shell` has a prompt such as:

```text
ola@localhost[default|maia]:~/git/maia$
```

Here, default is the active session and maia is the active workspace.

A monitored MAIA shell also shows the monitored shell name:

```text
ola@localhost[default|maia|shell1]:~/git/maia$
```

Here `shell1` is the monitored shell name.

The prompt uses additional characters to indicate missing or invalid context:

* An `!` is added to the session if the session does not exist.
* An `!` is added to the workspace if the workspace does not exist.
* An `§` is added to the workspace if the current directory is outside the workspace root.
* An `-` is shown as the workspace if there is no active workspace defined.

## maias

`maias` changes the active MAIA session for the current shell.

For example:

```bash
maias default
```

sets `default` as the active session.

## maiaforeachsession

```
maiaforeachsession <glob pattern> <command1> [<command2> [...]]
```

`maiaforeachsession` executes one or more commands for each session matching a specified glob pattern.

The first argument is a session glob pattern. Additional arguments are commands to execute.
For each matching session, all commands are evaluated as shell commands in the order they were specified
before proceeding to the next session.

For example:

```bash
maiaforeachsession "developer%*" "maia session" "maia tool refresh"
```

runs both `maia session` to print the session and `maia tool refresh` to refresh the tools for every session
whose name match "developer%*" glob pattern.

Multiple commands can therefore be applied consistently to a group of sessions without having to select
each session manually.

Advanced example:

```bash
maiaforeachsession "moddev%*" 's=$(maia session); m="${s#moddev%}" ; echo Adding files to $s from $m. ; maia file add $(cat proj/task/module-$m.txt)'
```

This extracts the session name from `maia session`, extract the subsession from the session name and add the files
listed in the file with the subsession name.
