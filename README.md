# Introduction

MAIA is a lightweight, command-line AI assistant designed to run on most Linux systems. It provides a
structured environment for working with AI models through sessions, workspaces, context and tools.

It is built around the Unix environment rather than requiring a separate application ecosystem.

It takes a different approach to many other AI tools. Rather than building a large integrated AI development
environment, it aims to provide a small, portable AI assistant that you can deploy almost anywhere you have a shell.

## The name

The name stands for Multipurpose Artificial Intelligence Assistant.
The individual letters can also be interpreted in other ways that reflect MAIA's characteristics.

The M can be interpreted as:
- Model-agnostic - because it does not depend on a specific AI model
- Multi-provider - because it can work with many different AI providers
- Modular - because it is built on modules and can be extended

The final A can be interpreted as:
- Assistant - because it is primarily intended to be used with direct user interaction
- Agent - because it can operate agentically when permitted

## Why MAIA

MAIA was developed around the following design principles.

### Portability

Easy to deploy anywhere you have a shell.

It is designed to run on most Linux installations, including older systems and stripped-down server deployments.

It has no compiled components or heavy runtime dependencies. Installation requires little more than copying
the files to a system and making the command available.

### Security

Open source, so its capabilities and behavior can be inspected and audited.

By default, the AI cannot directly make changes; changes are presented as suggestions that the user can review and explicitly apply. Additional capabilities can be granted through optional tools.

### Command-line First

Designed to work naturally from the command line and to be easy to incorporate into scripts, applications, and other software as a command-line tool.

### User-controlled Context

The user should have control over what the AI knows. History editing, session management, filesets, and context management make it possible to control what information is provided to the AI and how conversations are structured.

### Model and Provider Independence

No dependency on a specific AI model or provider. MAIA is designed to work with different AI APIs and providers, allowing the user to choose the models and services that best fit their needs.

# Installation & Setup

MAIA is designed to be portable and requires no compilation or system-wide installation.

It can be installed simply by copying the MAIA software to a directory, unpacking it first if necessary.

The directory where MAIA is installed is referred to as $MAIA_ROOT in the rest of this document.

## Prerequisites

MAIA requires the following software:

- `jq` 1.5 or later
- `curl`
- `perl`
- `bash`
- `coreutils`
- `awk` (mawk or gawk)
- `sed`

For optional functionality:

| Optional functionality | Depends on |
| --- | --- |
| maia shell enter | script from bsdutils |
| AWS API | xxd |

Some MAIA tools have additional dependencies:

| MAIA tool | Depends on |
| --- | --- |
| pandoc | pandoc |
| web-*-lynx tools | lynx |
| net-request-tcp | netcat |
| net-request-ssl | openssl |
| bc | bc |
| git-* tools | git |
| util-<x> tools | <x> |

## Install the dependencies

How to install the dependencies depends on the platform you use.

### Linux

On most Linux installations, the dependencies are already installed. If not, install them using your Linux distribution's package manager.

Example for apt-based systems, such as Debian and Ubuntu:
```bash
sudo apt-get install jq
```

### Microsoft Windows

On Windows, MAIA can run under WSL.

```powershell
wsl --install
```

How to configure WSL and install a Linux distribution is outside the scope of this document.

<!--
MAIA can also be run from Git Bash on Windows.

Open a PowerShell terminal and install the required software:

```powershell
winget install jqlang.jq
winget install --id Git.Git -e --source winget
```

Then start Git Bash.

**Windows support has not been fully tested.**
In particular, MAIA appears to run significantly slower under Git Bash than under WSL.
-->

## Install the software

The installation is easy. Simply copy to a directory where you want it to be and you are done.

MAIA can be installed from either a release archive or a Git repository.

### From a release archive

Unpack the software

```bash
tar xfz maia-<version>.tar.gz
```

This creates a `maia-<version>` directory. You can use this directory directly or copy it to the desired location.

### From a Git repository

Clone the repository:

```bash
git clone https://github.com/inguza/maia.git
```

This creates a `maia` directory. You can use this directory directly or copy it to the desired location.

<!--
**NOTE!** If you use Git for Windows, be aware that its default line-ending configuration may check out files using Windows-style `\r\n` line endings.

A clone using Windows-style line endings should not also be used from WSL or another Linux environment expecting Unix-style line endings. Use separate clones for Git Bash and WSL/Linux, or configure Git to use Unix-style line endings consistently before sharing a clone between environments.

If you plan to share the filesystem between Git Bash and WSL/Linux run the following to clone the repository:

```bash
git config --global core.autocrlf false
git clone https://github.com/inguza/maia.git
```
-->
## Configuration

### ~/.bashrc configuration

There are different ways to configure MAIA, depending on how you intend to use it.

- If you use a MAIA shell, MAIA can handle much of the shell configuration
  automatically.
- If you use MAIA from a regular Bash shell, you can configure the shell
  integration yourself.

You can also mix the two.

1) Enter a MAIA shell using `maia shell` or `maia shell enter`

   With this approach much of the shell configuration is handled automatically. It also provides more advanced functionality such as
   displaying the workspace in the prompt.

   You essentially just need to add `$MAIA_ROOT/bin` to the PATH or create an alias for the MAIA executable.
   
   ```bash
   alias maia="$MAIA_ROOT/bin/maia"
   ```
   or
   ```bash
   export PATH="$PATH:/path/to/maia/bin"
   ```

   If you want to manage PS1 with this approach you add the following to your `~/.bashrc` file.
   ```bash
   unset MAIA_PS1
   ```

2) Set up the helper functions yourself

   Add the following to your `~/.bashrc` file
   ```bash
   alias maia="$MAIA_ROOT/bin/maia"
   # For easy session setting
   maias() {
       export MAIA_SESSION="$1"
   }
   # To see the session in your bash shell
   # Change 35m to 34m to get blue path
   export PS1='\[\e]0;\u@\h${MAIA_SESSION:+[$MAIA_SESSION]}: \w\a\]${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]${MAIA_SESSION:+\[\033[01;36m\][\[\033[00m\]$MAIA_SESSION\[\033[01;36m\]]\[\033[00m\]}:\[\033[01;35m\]\w\[\033[00m\]\$ '
   ```

   For bash completions, copy the `etc/bash.completions` file to `/etc/bash_completion.d/maia` (the path may be different depending on your Linux distribution) or source it in your `~/.bashrc` file.

### Additional ~/.bashrc configuration

It may also be useful to set the prefered editor and log level. If `$MAIA_EDITOR` is not set it then it will fall back to `$EDITOR`.

```bash
export MAIA_EDITOR="emacs -nw"  # or your prefered editor
maia config term_loglevel INFO  # to get more information about what the tool does
```

### Used AI APIs

Depending on what AI provider you choose you configure it a little differenty. The access information
is set as environment variables, preferrbly in a ~/.bashrc file.

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

### MCP

Configure the MCP servers.

The MCP server syntax is:
```text
<name>=<endpoint>
```

Where `<name>` is a name you choose and `<endpoint>` is an MCP endpoint.

Two types of endpoints are supported:
- stdio - syntax 'stdio:command with optional arguments'
- https - syntax 'https://host/path'

Example:

```text
maia config mcp_servers '["name1=stdio:mcpcommand","name2=https://api.githubcopilot.com/mcp/"]'
```

#### stdio

The `stdio` endpoint type starts the specified command as an MCP server and communicates with it through standard input and output.

Examples:

```text
name1=stdio:mcpcommand
name1=stdio:mcpcommand --database /path/to/database
```

#### https

The `https` endpoint type communicates with a remote MCP server using HTTPS and the MCP Streamable HTTP transport.

Example:
```text
name2=https://api.githubcopilot.com/mcp/
```

For authentication, MAIA looks for an environment variable named `<NAME>_TOKEN`, where `<NAME>` is the uppercase MCP server name.

Example:

```text
export NAME2_TOKEN='<tokenhere>'
```

The token is sent as `Authorization: Bearer <token>`.

---

# Key Concepts

## [Scope](docs/scope.md)

Hierarchical levels for defining configuration and resources, allowing settings to be inherited and overridden from system to session.

## [Shell](docs/shell.md)

The maia shell is a standard bash shell with extra convenience functionality on top.

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

3. **Allow tools and skills**
   Allow tools (this is a small set, there are more tools available):

   ```bash
   maia tool --scope session replace "core-*" "file-*" "context-*" "change-*"
   ```
   
   Allow skills and make sure they are in context.

   ```bash
   maia skill --scope session --remember replace "file"
   ```

4. **Manage files**
   Add relevant files to provide context for the AI.

   ```bash
   maia file remember pathtofile1
   maia file forget pathtofile1
   ```

5. **Compose messages**

   Send a message from command line:
   ```bash
   maia "Send this text to the AI"
   ```

   Send a message using an editor to compose it:
   ```bash
   maia compose
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
