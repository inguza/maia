# Introduction

MAIA is a command-line tool designed to help you manage conversations with AI APIs in a structured way.

## The name

The name stands for Multi-purpose Artificial Intelligence Assistant.
The individual letters can also be interpreted in other ways that reflect MAIA's characteristics.

It supports managing:
- sessions
- workspaces
- files , change
suggestions, and more, enabling a powerful AI-assisted workflow.

The name is an acronym for Multi-purpose Artificial Intelligence Assistant, but
it can be interpreted as an acronym for other things as well.

The M can be interpreted as:
- Model-agnostic - because it does not depend on a specific LLM model
- Multi-provider - because it can work with many different AI providers
- Modular - because it is built on modules and can be extended

The A can be interpreted as:
- Assistant - because it is primarily intended to be used with direct user interaction
- Agent - because it has agentic properties (if allowed to)

## Why MAIA

MAIA was developed because no other tools, at the time, could meet the following design principles.

### Compatibility

Minimal dependencies, with a preference for common, well-established tools available on most Linux installations, including really old ones and stripped-down server deployments.

### Security

Open source, so its capabilities and behavior can be inspected and understood.

By default, the AI cannot directly make changes; changes are presented as suggestions that the user can review and explicitly apply. Additional capabilities can be granted through optional tools.

### Command-line First

Designed to work naturally from the command line and to be easy to incorporate into scripts, applications, and other software as a command-line tool.

### User-controlled Context

The user should have control over what the AI knows. Extensive history editing, session management, filesets, and context management make it possible to control what information is provided to the AI and how conversations are structured.

### Model and Provider Independence

No dependency on a specific AI model or provider. MAIA is designed to work with different AI APIs and providers, allowing the user to choose the models and services that best fit their needs.


# Installation & Setup

## Prerequisites

Ensure you have the following software installed:

- `jq` 1.5 or later
- `curl`
- `perl`
- `bash`

It can optionally use the following tools:

- pandoc
- lynx
- GNU utilities: grep, sort, sed, uniq, wc, tail, head, patch, diff, head, find, ls
- BSD utilities: file
- netcat

## Install the software

The installation is easy. Simply copy to a directory where you want it to be and you are done.
The directory where you want MAIA to reside is called `$MAIA_ROOT` below.

1. Unpack the software

   ```bash
   tar xfz maia-xxxx.tar.gz
   ```

2. Copy where you want it to be

   ```bash
   mkdir -p /some-path
   cp -a maia-<version>/* /some-path
   ```

## Configuration

### Aliases

The maia executable can be called directly but for easier use copy the content of `$MAIA_ROOT/etc/bashrc` to, for example, your ~/.bashrc file.

It may also be useful to set the preferred editor and log level. If `$MAIA_EDITOR` is not set it then it will fall back to `$EDITOR`.

```bash
export MAIA_EDITOR="emacs -nw"  # or your preferred editor
maia config term_loglevel INFO  # to get more information about what the tool does
```

### Used AI APIs

Depending on what AI provider you choose you configure it a little differenty. The access information
is set as environment variables, preferrably in a ~/.bashrc file.

#### OpenAI

```bash
export OPENAI_API_KEY='your_api_key_here'
```

#### AWS Bedrock

```bash
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
maia config api_base_url https://bedrock-runtime.us-east-1.amazonaws.com
maia config model someavailablemodel
maia config file_handling_mode APPEND
maia config send_hook "~/.maia/send-hook.sh"
```

For AWS Bedrock a send hook can be useful to automatically set the
needed environment variables. Set it using send_hook configuration option.

#### Optional extra authentication headers

```bash
export MAIA_CURL_EXTRA_HEADERS=$'X-My-Auth: mytoken\nX-Another-Header: value'
```

---

# Key Concepts

## [Scope](docs/scope.md)

Hierarchical levels for defining configuration and resources, allowing settings to be inherited and overridden from system to session.

## Workspace

A project directory that provides the context and resources for one or more sessions.

## Session

A persistent conversation with an AI, including its history and context.

## Filesets and Files

Filesets define which files are available as context for a session, allowing the user to control what the AI can see.

## Change Suggestions

Proposed changes to files that can be reviewed and explicitly applied by the user.

## [Tools](docs/tools.md)

Optional external capabilities that can be made available to the AI to perform actions beyond conversation.

---

## Typical Workflow

1. **Initialize a workspace**

   ```bash
   maia workspace create <workspacename>
   ```

2. **Create and select session**

   Create the session:
   ```bash
   maia session create <sessionname>
   or
   maia session create <sessionname> --workspace <workspacename>
   ```

   Associate it with a workspace:
   ```bash
   maia session set <sessioname> --workspace <workspacename>
   ```

   Select the session:
   ```bash
   maias sessionname1
   ```

3. **Manage files**
   Add relevant files to provide context for the AI.

   ```bash
   maia file remember pathtofile1
   maia file forget pathtofile1
   ```

4. **Compose messages**

   Send a message from command line:
   ```bash
   maia "Send this text to the AI"
   ```

   Send a message using an editor to compose it:
   ```bash
   maia compose
   ```

   By default maia parses the response and procuce change suggestions.

5. **Parse AI responses into changes**
   Review and apply changes to your files.

   ```bash
   maia change list
   maia change show
   maia change apply
   ```

6. **Check history**

   Read the last response:
   ```bash
   maia history
   ```

   Read the full history:
   ```bash
   maia history all
   maia history -
   ```

---

# Additional information

## Notes

- When commands are ambiguous, text starting with a capital letter or quoted with spaces is treated as user input.
- `<text-or-file>` can be:
  - a word
  - quoted text
  - `read` (stdin)
  - `compose` (open editor and add new content)
  - `edit` (edit inline)
  - `@snippetname` (reference snippet text)
- Multiple `<text-or-file>` arguments are appended as new lines.
- Use quoted globs carefully when managing files.

## Help and Documentation

For detailed command usage, run:

```bash
maia --help
maia <command> --help
```

This README provides an overview; use the CLI help for command-specific details.

## Support

For issues, feature requests, or questions, please visit the project repository or contact the maintainers.

https://github.com/inguza/maia

## Authors

Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>

## Licensing

This software is available under the GNU General Public License v3.0 and under
separate commercial licensing terms.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, version 3 of the License.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
