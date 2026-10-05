# Instructions

Instructions are named pieces of guidance that MAIA can include in the model context. They may be explicitly remembered or loaded automatically when their path or enabled tools match their metadata.

## Instruction files

A named instruction is a directory containing an `INSTRUCTION.md` file. The directory name is the instruction name. The file contains the instruction description and content.

```text
<instruction-name>/
└── INSTRUCTION.md
```

Workspace path-based instructions use a different convention. A `MAIA.md` file at the workspace root or in a directory below it applies to the corresponding workspace path when files from that path are included in the context.

```text
<workspace-root>/
├── MAIA.md
└── <directory>/
    └── MAIA.md
```

Instructions can be supplied by the installation, standard scopes, profiles, plugins, and configured additional instruction paths. More-specific definitions take precedence when names collide.

## `INSTRUCTION.md` format

The first part of an `INSTRUCTION.md` file may contain a metadata header delimited by a line containing three hyphens (`---`). The header consists of one field per line in the form `field: value`. The header is removed when the instruction content is rendered; the Markdown after the closing delimiter is the instruction itself.

The following fields are recognized:

- `description` — Short description shown when the instruction is listed or made available. It is also used as part of the heading when the instruction is included in the model context.
- `any-path` — Space-separated file-path patterns. The instruction is loaded automatically when at least one file in the current file context matches one of these patterns.
- `any-tool` — Space-separated tool-name patterns. The instruction is loaded automatically when at least one enabled tool matches one of these patterns.
- `all-path` — Space-separated file-path patterns. The instruction is loaded automatically only when every listed pattern matches a file in the current file context.
- `all-tool` — Space-separated tool-name patterns. The instruction is loaded automatically only when every listed pattern matches an enabled tool.
- `loadable` — Controls whether an instruction that is not automatically loaded is shown as available for explicit loading. The default is enabled; set it to `false` to hide the instruction from the available-instructions list. This does not prevent an explicitly remembered instruction from being included.

The path and tool fields use MAIA's wildcard-style patterns. Within an `any-path` or `any-tool` field, the patterns are alternatives: one matching path or tool is sufficient. Within an `all-path` or `all-tool` field, every pattern in that field must match. Conditions from different fields are combined with **AND**. Thus, when several fields are specified, every specified field must pass: at least one `any-path`, at least one `any-tool`, every `all-path` pattern, and every `all-tool` pattern.

For example:

```markdown
---
description: Guidance for Python files using the test tools
any-path: \\*.py tests/**
any-tool: python-* pytest-*
loadable: true
---

Use the project's Python conventions. Prefer the available test tools when
checking or changing Python code, and run the relevant tests after a change.
```

An instruction with no path or tool conditions is loaded automatically. Metadata fields that are not listed above are ignored.

## Instruction selection

The instruction command manages the explicitly loaded instruction names in `instructionset.txt`. Instructions may also be loaded automatically when their metadata matches files in the current context or enabled tools. An instruction that is not automatically loaded may be available for explicit selection, depending on its `loadable` metadata.

The selected instructions are rendered into the model context. `MAIA.md` path-based instructions are handled separately and are added for the workspace paths represented by the session's file context.

Use the command help for operations and options:

```bash
maia instruction --help
```

Use `maia session instructions` to inspect the instruction content currently associated with the session.
