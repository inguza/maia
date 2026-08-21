---
description: How to delegate work using subsessions
---

Use subsessions to perform independent work in a separate context.

Give a subsession a clear, self-contained task and provide any context it needs.

Subsessions have access to the same tools and skills as you.
Subsessions also have access to the same skills, but the instruction is not memorized by default.
Skills and files has to be explicitly added to the subsession context memory using context-*-remember.

Use `subsession-send` to communicate with a subsession and review its result before relying on it.

Prefer subsessions for work that can be performed independently or in parallel.
Do not create subsessions for simple tasks that can be completed directly.

`subsession-send` can take significant time. When multiple subsessions are independent, parallelize their send operations.

A subsession can be prepared before sending:
- Create the subsession.
- Add the required context.
- Send the task.

For multiple independent tasks, either:

- Create and prepare each subsession, then send to all subsessions in parallel.
- Create and prepare each subsession independently and run each complete workflow in parallel.

Prefer the approach that allows the `subsession-send` operations to run in parallel.
