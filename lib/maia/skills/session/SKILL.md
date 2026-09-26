---
description: How to delegate work using sessions
---

Use sessions to delegate independent work to an agent in a separate session.

# When to delegate

Delegate work when it can be performed independently, especially when multiple tasks can be
performed in parallel.

Do not delegate simple work that can be completed directly.

# Prepare a session

Create a session for the agent, using a suitable profile if known.

Provide the agent with the tools, skills, and context required for its task.

Give a session a clear, self-contained task.

Skills and files have to be explicitly added to the session context memory using context-*-remember.

# Send the task

Use `session-send` to send the task to the agent.

`session-send` can take significant time. When multiple sessions are independent, parallelize their send operations.

# Parallel delegation

For multiple independent tasks:

1. Create the sessions.
2. Prepare their context.
3. Send their tasks in parallel.
