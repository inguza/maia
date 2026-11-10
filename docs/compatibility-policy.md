# Compatibility Policy

MAIA follows [Semantic Versioning](https://semver.org/). This policy describes what compatibility
means within a MAJOR version.

## Supported interfaces

The following are considered supported interfaces and are kept backwards-compatible:

- Commands, subcommands and options as documented in the maia help (`maia --help` and `maia subcommand --help`).
- [Configuration parameters and environment variables](config.md)
- File format and mechanisms for:
  - [Skills](skills.md)
  - [Instructions](instructions.md)
  - [Custom tools](tools.md)
- Scope names

## User data

The following user-data will remain usable across updates. Internal formats may change between releases,
in which case migration may be required using `maia update upgrade`.

 - Maia home configuration
 - [Sessions](session.md) configuation and history
 - Workspace configuration
 - [Profile](profile.md) configuration
 - Fileset lists and [filespecs](filespecs.md) definition
 - [Changes](changes.md) format
 - System prompt configuration
 - Allowed tool lists
 - Allowed and memorized skill lists
 - Memorized instruction lists

## Shell

The following commands in `maia shell` will remain available.

- maia
- maias
- maiaforeachsession

## What may change

The following are not covered by compatibility guarantees:

- Internal implementation details, undocumented file formats and internal shell files.
- GUI layout, appearance and interaction model.
- Built-in tool and skill definitions, which may evolve and require refreshing after updates.
- Undocumented behavior and output formats.
- Hooks mechanism
- Plugins mechanism
