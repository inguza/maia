# Tools

`maia` supports integration with external tools that can be invoked by the AI model through function calls. These tools enhance the AI's capabilities by allowing it to perform actions or retrieve information from your environment.

## Tool Definitions (`.td` files)

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

## Tool Discovery and Enabling

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

## Additional Tool Paths

You can configure additional directories to be scanned for tool definitions using the `additional_tools_path` configuration variable. This variable can be a colon-separated list of directories, allowing you to include custom or third-party tools outside the standard scopes.

Example:

```bash
maia config additional_tools_path "/opt/maia-tools:/home/user/custom-tools"
```

`maia` will then scan these directories for `.td` files and treat them as if they were in an `extra` scope with the lowest priority.

## Enabling tools

Tools are enabled using the `maia tool` command. It is scoped in the same way as system and user prompts are.

There are two files maintained.
- toolset.txt with the list of enabled tools
- toolset.json with the enabled tool definition file

If the tool definitions are updated after the `maia tool` command is run it may result in an out-of-date toolset.json file.
You can check that by executing `maia tool verify` and if it is out of date, you can update it with `maia tool refresh`

## Using Tools in AI Conversations

When sending prompts to the AI, `maia` includes the metadata of all enabled tools in the request, allowing the AI to call these tools as functions.

When the AI requests a tool function call, `maia` executes the corresponding tool executable with the provided JSON arguments and returns the result back to the AI.

*This design allows flexible and extensible integration of external functionality into AI interactions with `maia`.*
