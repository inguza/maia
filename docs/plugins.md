# Plugins

A plugin provides a convenient way to install additional functionality in MAIA.

Each plugin is stored in its own directory, named after the plugin.
The directories within the plugin contain the functionality it provides.

```text
<pluginname>/
├── instructions/
│   ├── <instruction 1>
│   ├── ...
│   └── <instruction N>
├── tools/
│   ├── <tool 1>
│   ├── ...
│   └── <tool N>
├── profiles/
│   ├── <profile 1>
│   ├── ...
│   └── <profile N>
└── skills/
    ├── <skill 1>
    ├── ...
    └── <skill N>
```

Each directory is optional, and a plugin can provide zero or more items of each supported type.

The directories searched for plugins can be configured. The default is:

```text
/etc/maia:<MAIA_INSTALL_DIR>/lib/maia/plugins
```

This can be overridden by the `MAIA_PLUGIN_PATH` environment variable:

```text
export MAIA_PLUGIN_PATH="/etc/maia:/home/user/software/maia/lib/maia/plugins:/project/maia/plugins"
```
