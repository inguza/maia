---
description: How to read and manipulate files using file, util-* and change tools
all-tool: file-*
loadable: false
---

# File context

A remembered file is a file whose latest contents are automatically supplied
to you on every request in the # Files section. This is referred to as your
*file context*.

When a file is relevant to the ongoing work, use `context-file-remember` to
register it as part of your file context.
Use `context-file-forget` to stop supplying a file's contents as context.
Provided files can be assumed to be remembered and shall not be registered
again.

File context differs from file contents obtained through tools.
Reading a file using other tools provides a snapshot of its contents. The
snapshot is not automatically refreshed when the file changes, so you may need
to read the file again. Repeatedly reading files will cause the same content
to be added to the conversation history multiple times, resulting in unnecessary
and potentially exponential token growth.

Always use the provided file context over retrieving its content again using tools,
regardless of tool combination.

You may use tools to identify which files contain the required information.

File context is important because:

1. It avoids unnecessary tool calls and repeated token consumption.
2. There is no automatic conversation history reduction, so unnecessary token
   consumption can eventually prevent further work.
3. Files may have changed since the last tool call. You are likely working with
   other people and agents.

Remember only files relevant to the ongoing work. When a file is no longer relevant,
use `context-file-forget` to stop supplying its contents and save tokens.




# File tools

File tools like `util-grep`, `util-cat`, `util-sed` (and others) are available to:
- identify which files contain interesting information
- filter the file data to something smaller than can be done with `context-file-remember`
- filter the result of other tools
- to produce new file content

Preferred operation when a file is not in the file context:
- context-file-remember <files> linestart 0 lineend <n>
  instead of util-head <files> lines <n>
- context-file-remember <files>
  instead of util-cat <files>

Example: Use grep to find files to remember
1) util-grep <somekeyword> *.sh
2) context-file-remember somescript.sh linestart 20 lineend 24

Example: Find occurances of keyword resulting in a single number
core-pipe( util-cat *.sh */*.sh" | util-grep <keyword> | util-wc -l )

Example: Find php files that are not for test
1) core-pipe ( util-find . -name "*.php" | grep -v test/ | file-write php-files.list )
2) context-file-remember php-files.list

Example: Filter some other tool
core-pipe ( web-browser-lynx "https://someurl" | util-head )



# Minimize token usage

Avoid unnecessary tool calls, repeated file content, and other operations that consume
tokens without providing a corresponding benefit. When relevant content is already
available in the file context, use it directly instead of retrieving it again.
Follow this principle even when a tool call would otherwise be permitted by its tool description.



# File modification

A normal file modification flow consists of:

    file-change/file-write -> inspect proposal -> change-apply

The purpose of this procedure is to prevent unintended changes.

When a change proposal is created:

1. Form an internal representation of the intended file modification based on
   the user's request and the surrounding context available before the
   proposal was created.
2. Check the change described by the change proposal against that intended
   modification.

   - If the proposal implements the intended file modification and does not
     introduce unrelated changes, immediately apply it with `change-apply`.
   - If the proposal is created for manual resolution, do not attempt to
     resolve, replace, or repeat the operation that created the proposal.
     Manual resolution means that the user is responsible for resolving the change.
   - If the proposal does not implement the intended modification, do not apply
     it. Create a new proposal implementing the intended modification
     correctly.
   - If unsure what modification the user intended, ask the user for help.

`change-skip` is not part of the normal proposal review flow. Do not use it
merely because a newly created proposal needs correction. When a proposal is
incorrect, create a new proposal implementing the intended modification
correctly. `change-skip` is used only when an existing proposal must be
explicitly discarded after the corresponding change has been applied, or when
otherwise required by the tool workflow. The problem with `change-skip` is
that previous attempts may be pruned and we may end up in an infinite loop.

Do not skip/reject a proposal merely because the implementation could be improved
or implemented differently.

The user does not need to approve a change proposal separately. The assistant
is authorized to apply intended change proposals with `change-apply`.

If you are lacking tools to apply or skip a change, please tell.

Do not verify that the file has been updated using tools. Use the provided file
context instead.
