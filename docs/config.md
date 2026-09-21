# Config

## API and model

* `api_base_url` — Base URL of the API endpoint.
* `api_type` — API type to use. `AUTODETECT` automatically determines the API type.
* `model` — Model to use for requests.
* `file_handling_mode` — Controls how file content is handled when constructing model requests.
* `max_input_tokens` — Maximum number of input tokens for a session. The token count is estimated to the number of characters/4. This is a client side limit.
* `max_output_tokens` — Maximum number of output tokens requested. This is a limit sent to the API provider.
* `tool_iteration_limit` — Maximum number of tool iterations in a model interaction.
* `tool_loop_prevent` — Tools for which repeated tool-loop execution is prevented.
* `send_hook` — Optional hook executed when preparing or sending a request. This can be used, for example, to read the API credentials.

### API parameters

* `temperature` — Controls randomness in model output.
* `top_p` — Nucleus-sampling parameter.
* `frequency_penalty` — Penalizes tokens according to their frequency in the generated output.
* `presence_penalty` — Penalizes tokens that have already appeared in the generated output.
* `n` — Number of completions requested.
* `stream` — Whether model responses are streamed.

## Sessions

* `default_profile` — Profile used by default.
* `allowed_profiles` — Profiles available to agents.

## Agent managed sessions

* `agent_session_prefix` — Prefix used for agent session names. It can be set to the empty string to allow agent-to-agent communication.
* `agent_session_allowed` — Sessions an agent is allowed to list and access.
* `default_agent_skill_allow` — Limits which skills an agent may allow. An agent can only allow skills permitted by this setting.
* `default_agent_skill_forget` — Skills excluded from the agent's remembered skill context by default.
* `default_agent_skill_remember` — Skills remembered by default for an agent. Can only remember allowed skills.
* `default_agent_skill_restrict` — Scope used to restrict agent skill access.
* `default_agent_tool_allow` — Limits which tools an agent may allow. An agent can only allow tools permitted by this setting.
* `default_agent_tool_restrict` — Scope used to restrict agent tool access.
* `default_allowed_tool_effects` — Tool effects allowed by default. Example: ["limited-write", "write"]

gent_session_allowed` and all `default_agent_*` allow, forget, remember, and restrict parameters are space-separated lists of glob patterns.

## Workspace and files

* `default_workspace` — Workspace used by default.
* `default_session_filesets` — Filesets automatically associated with a session.
* `default_session_extra_send_filesets` — Additional filesets automatically sent with session requests.
* `default_filter` — Default file context filter.

## Skills and tools

* `additional_skill_paths` — Additional paths from which skills are discovered.
* `additional_tool_paths` — Additional paths from which tools are discovered.
* `mcp_servers` — MCP servers configured for MAIA.

## Terminal and logging

* `http_logging` — Enables HTTP request/response logging.
* `term_loglevel` — Minimum terminal log level.

## Legacy parse handling (deprecated)

* `auto_add_new_files_on_apply` — Automatically adds newly created files to the relevant file context when a change is applied.
* `auto_parse` — Automatically parses files when they are added or processed.
* `prune_mode` — Strategy used when pruning context/history.
* `prune_when_applied` — Whether context is pruned after an applied change.
* `prune_when_skipped` — Whether context is pruned after a skipped change.
* `splice_allowed_files` — Regular expression specifying which files may be spliced into context.
* `tab_width` — Tab width used when parsing the proposed files.

