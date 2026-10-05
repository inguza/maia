# Skills

Skills are named, discoverable capabilities that provide instructions and executable scripts for an AI interaction. A skill is available only when it is allowed, and its instructional content can be remembered separately.

## Skill files

A skill is a directory containing a `SKILL.md` file. The directory name is the skill name. The file provides the skill description and instructions; the same directory may also contain executable scripts that can be run as skill operations.

```text
<skill-name>/
├── SKILL.md
└── <skill scripts and supporting files>
```

MAIA discovers skills from the installation, standard scopes, profiles, plugins, and configured additional skill paths. More-specific definitions take precedence when names collide. A skill directory is discovered only when its `SKILL.md` file is present.

## Skill selections

The skill command manages two related selections in the selected scope:

- `skillset.txt` contains the allowed skill names or patterns. Only allowed skills may be used by the AI.
- `skillsetcontext.txt` contains the skills whose instructional content is remembered and included in the context.

The generated files `skillset.gen` and `skillsetcontext.gen` contain the corresponding rendered descriptions and instructions used in the prompt. They are derived files; `maia skill refresh` updates them and `maia skill verify` checks that they are synchronized.

The allowed and remembered selections are related but distinct. A skill must be allowed before it can be remembered. Remembering a skill includes its instructional content in the context, while allowing a skill makes it available without necessarily including all of its instructions in every request.

Skills can also be run directly. Direct execution is not recorded as a conversation message; permissions and the selected workspace still apply.

Use the command help for operations and options:

```bash
maia skill --help
```
