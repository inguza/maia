# Contributing to MAIA

## Portability

MAIA is intended to run in a wide range of Unix-like environments, including Git Bash on Windows.
Keep the implementation portable across Bash environments.

### Avoid Bash process substitution

Do **not** use Bash process substitution:

```bash
<(command)
```

or:

```bash
>(command)
```

Process substitution is not sufficiently portable, particularly on Windows/Git Bash.

Prefer alternatives such as:

* `mapfile_from_command` for capturing line-oriented command output into an array.
* Temporary files when data is large or needs to be consumed by another command.
* Ordinary pipes where they do not require modifying shell variables in a subshell.

In particular, do not introduce process substitution merely as a convenient way to connect commands or provide a command's output as a file argument.

When large data is involved, avoid replacing process substitution with command substitution if that would unnecessarily put the data into a Bash variable or command-line argument. Prefer a temporary file in those cases.

This restriction applies to new code and when modifying existing code: if practical, replace process substitution encountered in the code being changed.

### Remember line ending

Linux/unit and Windows/DOS line endings are different. Make sure to handle that.
This typically means that when reading a line the \r character should be stripped.

We shall also make sure we read the last line even if it does not end with a newline.

    while IFS= read -r line || [[ -n "$line" ]]; do
       line="${line%$'\r'}"

### Git Bash path substitution

Git Bash is a little special. It converts /c ... to C:.
We want that for many cases, but not for the path of the workspace.

For that we use MSYS_NO_PATHCONV=1 when path arguments shall be preserved.
