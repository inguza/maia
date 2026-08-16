# maia CLI Tool

`maia` is a command-line tool designed to help you manage conversations with AI APIs in a structured way. It supports managing sessions, workspaces, files, change suggestions, and more, enabling a powerful AI-assisted development workflow.

---

## Licensing

Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>

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

## Key Concepts

### Workspace

A **workspace** represents a project directory with associated metadata, filesets, and configurations. It helps organize your AI interactions in the context of a specific project.

- Think of it as a container for all your project-related files and AI conversations.
- Workspaces isolate projects and maintain context across sessions.
- Changes are described as relative to the workspace root.
- Tools are executed with the current working directory set to the workspace root.

### Session

A **session** is a conversation or interaction context with the AI, including user messages, history, and system prompts.

- Sessions allow you to maintain separate dialogues or experiments.
- You can create, switch between, and manage multiple sessions within a workspace.

### Filesets and Files

- **Filesets** are named collections of files within a workspace, helping you specify which files are relevant for your AI interactions.
- You can add, remove, or list files in filesets to tailor the context sent to the AI.

### User Outbox and System Prompt

- The **user outbox** is where you compose messages to send to the AI.
- The **system prompt** sets the AI's behavior or context globally or per session.

### Change Suggestions

- Parsed AI assistant responses can be converted into **changes** — suggested edits or patches to your files.
- You can review, edit, and apply these changes to your workspace files.

### Snippets

- Named text snippets that can be referred to for frequently written text statements.

### Tools

- Tools that the AI can call

---

## Scope

The `maia` CLI tool uses a layered configuration and data management model called **Scopes** to organize settings, snippets, system prompts, and other resources.

Each scope corresponds to a level of specificity and persists in distinct directories or files. This layered approach allows flexible customization and inheritance of configurations and resources.

### Scope Levels (From Most Specific to Least Specific)

- **Session**
  The most specific scope, tied to the current conversational session. Session scope stores history, outbox, system prompts, and snippets that apply only to that session.

- **Workspace**
  Represents the current project or workspace. Workspace scope holds project-level configuration, filesets, and shared snippets or prompts that apply to all sessions within the workspace.

- **Home**
  The local MAIA home directory, usually located at `.maia` under your current working directory or a configured path. Home scope contains user-specific configuration and snippets that override system defaults but are less specific than workspace or session settings.

- **User**
  The user’s global configuration directory, typically `~/.maia` or a user-defined path. User scope settings apply across all workspaces and sessions on the machine for the user.

- **System**
  The system-wide configuration, usually under `/etc/maia`. This scope is read-only and provides default system-level settings and snippets.

- **Default**
  Built-in defaults hardcoded within the tool itself. This is the fallback for any configuration or resource not defined in higher scopes.

### How Scopes Work

When the tool reads configuration or resources, it merges values from these scopes in order of specificity: session overrides workspace, which overrides home, and so forth. This ensures that more specific settings take precedence.

When writing configuration or snippets, the tool allows targeting a specific scope or uses sensible defaults (e.g., writing to the home scope for user configuration).

This scope hierarchy enables:

- Project- and session-specific customization without affecting global settings.
- Global defaults for consistency across projects.
- Easy overrides for experiments or temporary changes in a session.

### Examples of Use

- Editing the system prompt for a single session without affecting other sessions or workspaces.
- Defining a fileset in the workspace scope that is shared by all sessions.
- Setting an API key or global preference in the user or home scope.
- Providing default snippets in the system scope that can be overridden in user or session scopes.

---

**Tip:** You can explicitly specify the scope when managing configuration, snippets, or prompts using the `--scope` option in commands.

---

## Tools

`maia` supports integration with external tools that can be invoked by the AI model through function calls. These tools enhance the AI's capabilities by allowing it to perform actions or retrieve information from your environment.

### Tool Definitions (`.td` files)

Tools are defined through metadata files with the `.td` extension. These JSON files describe the tool's interface, including its name, description, parameters, and the command used to execute it.
Multiple tools can be defined in one `.td` file.

Each `.td` file should be a valid JSON object with the following fields:

- `name` (string): The fully qualified name of the tool function, typically namespaced with dots (e.g., `"git.status"`).
- `description` (string): A human-readable description of the tool's purpose, shown to the AI model.
- `command` (string or array): The executable command or script that implements the tool.
- `parameters` (JSON Schema object): Specifies the expected input parameters for the tool function.
- `strict` (boolean): Whether strict JSON schema validation should be enforced on the input.

**Example:**

```json
{
  "name": "file.read",
  "description": "Read the contents of a file",
  "command": "file-read.sh",
  "parameters": {
    "type": "object",
    "properties": {
      "path": {
        "type": "string",
        "description": "Path to the file to read"
      }
    },
    "required": ["path"]
  },
  "strict": true
}
```

The command is the executable to run and the executable is searched for in the same order as Tool Discovery takes place (described below).

The command string can have space, and in that case the text after the space is the command arguments.

**Interface Contract**

The tool executable shall work in the following way:

- Receives its input parameters as JSON on standard input (`stdin`).
- Output written to standard output (`stdout`).
- Diagnostic messages can be written to standard error (`stderr`).
- Exit with code `0` to indicate success; any non-zero exit code indicates failure.
- The working directory is the current workspace root.
- Environment variables are inherited normally; tools should not depend on `maia`-specific environment variables.

**Example: How to test the tool:**

```bash
args_file=something
echo '{"path": "README.md"}' > $args_file
echo '' | ./file-read.sh 3<$args_file
```

The script reads the JSON parameters from `stdin`, processes the request, and writes the output to `stdout`.

### Tool Discovery and Enabling

`maia` discovers tools by scanning `.td` files across multiple scopes, following the following scope order:

1. MAIA built in tools
2. System (typically /etc/maia/tools)
3. Home (.maia/tools subfolder of $MAIA_HOME if set or ~/ if not)
4. User (a .maia dir in any of the sub-directories if any exist)
5. Workspace directory (.maia/tools subfolder)
6. Session directory tools subfolder
7. Additional tool paths (described below)

If multiple `.td` files define a tool with the same name, the last definition takes precedence, allowing overrides.

By default, all tools are **disabled**. Tools must be explicitly enabled in a scope by adding their names or matching patterns to a `tools.txt` file in that scope.

### Additional Tool Paths

You can configure additional directories to be scanned for tool definitions using the `additional_tools_path` configuration variable. This variable can be a colon-separated list of directories, allowing you to include custom or third-party tools outside the standard scopes.

Example:

```bash
maia config additional_tools_path "/opt/maia-tools:/home/user/custom-tools"
```

`maia` will then scan these directories for `.td` files and treat them as if they were in an `extra` scope with the lowest priority.

### Enabling tools

Tools are enabled using the `maia tool` command. It is scoped in the same way as system and user prompts are.

There are two files maintained.
- tools.txt with the list of enabled tools
- tools.json with the enabled tool definition file

If the tool definitions are updated after the `maia tool` command is run it may result in an out-of-date tools.json file.
You can check that by executing `maia tool verify` and if it is out of date, you can update it with `maia tool refresh`

### Using Tools in AI Conversations

When sending prompts to the AI, `maia` includes the metadata of all enabled tools in the request, allowing the AI to call these tools as functions.

When the AI requests a tool function call, `maia` executes the corresponding tool executable with the provided JSON arguments and returns the result back to the AI.

*This design allows flexible and extensible integration of external functionality into AI interactions with `maia`.*

---

## Typical Workflow

1. **Initialize or select a workspace**
   Create a workspace for your project or use an existing one.
   Workspaces help keep your AI interactions organized by project.

   ```bash
   maia workspace create
   ```

2. **Create or switch to a session**
   Start a new session for your conversation or use an ongoing one.
   Sessions hold your message history and user outbox.

   ```bash
   maia session create sessionname1
   ```

3. **Manage files and filesets**
   Add relevant files to filesets to provide context for the AI.
   Use filesets to control which files are included in AI prompts.
   Use filters to show partial file content.

   ```bash
   maia file add pathtofile1
   maia file delete pathtofile1
   ```

4. **Compose messages**
   Append or edit messages in the user outbox.
   Use `maia send` to send messages and receive AI responses.

   ```bash
   maia "Send this text to the AI"
   maia compose
   maia user edit
   ```

5. **Review history**
   Inspect past conversations and changes.
   Export or search history as needed.

   ```bash
   maia history
   ```

6. **Adjust history**
   The history data can be adjusted if needed.
   The most common is to prune the history to save tokens.
   The method of pruning can be configured with the prune_mode
   configuration option. The default is to reduce the size by
   replacing large blocks with a <<BLOCK #n pruned >> text, but
   'cut' is also available to reduce the whole message.

   ```bash
   maia history prune -
   ```

7. **Parse AI responses into changes**
   Extract suggested edits from AI replies using `maia parse`.
   Review and apply changes to your files.

   ```bash
   maia parse
   maia change list
   maia change show
   maia change apply
   ```
   The default is to prune the history when a change is appled or
   skipped but this can be controlled by the configuration attributes
   prune_when_applied and prune_when_skipped. When applying or skipping
   prune_mode=prune is always used.
---

## Why Use maia?

- Structure AI interactions for reproducibility and context management.
- Manage multiple projects and conversation threads cleanly.
- Integrate AI-generated suggestions directly into your codebase.
- Maintain clear separation between user messages, system prompts, and AI responses.
- Manage files relevant to AI prompts efficiently.

---

## Installation & Setup

### Prerequisites

Ensure you have the following software installed:

- `jq` 1.5 or later
- `curl`
- `perl`
- `bash`

### Unpack the maia package

```bash
tar xfz maia-xxxx.tar.gz
```

### Make an alias to `maia`

```bash
alias maia=/path/to/maia-xxxxx/maia
```

### Configuration

#### General

```bash
export MAIA_EDITOR="emacs -nw"  # or your preferred editor
maia config term_loglevel INFO  # to get more information about what the tool does
```

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

## Help and Documentation

For detailed command usage, run:

```bash
maia --help
maia <command> --help
```

This README provides an overview; use the CLI help for command-specific details.

---

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

---

## Support

For issues, feature requests, or questions, please visit the project repository or contact the maintainers.

---

Thank you for using `maia`!
