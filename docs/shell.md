# Shell

The maia shell is a standard bash shell with some extra functionality added on top.

* Showing the active session in the prompt. Will add ! in case the session does not exist.
* Showing the active workspace in the prompt. Will add ! in case teh workspace does not exist and § in case
  the current directory is outside the workspace root.
* For monitored shells show the shell name.
* maias command to set the active session

Example of a maia shell
```text
ola@localhost[default|maia]:~/git/maia$
```
In this example `default` is the session name and `maia` is the workspace name.

Example of a monitored maia shell
```text
ola@localhost[default|maia|shell1]:~/git/maia$
```
In this example `default` is the session name, `maia` is the workspace name and `shell1` is the monitored shell name.
