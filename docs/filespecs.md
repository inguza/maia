# File specifier

## General file specification

Syntax:

```
<path>[:<type>[:<typespecific>]][|<filter>]
<path>[:<typespecific>][|<filter>]
<provider>#<mcp url>[|<filter>]
<name/path>[:<type>[:<typespecific>]]@<url>
```

`<path>` is the path to the local file relative to the workspace root.

`<name/path>` is a name used reference the content in text.

`<type>` is one of:
 - `text` -- Text file
 - `image` -- Image file
 - `document` -- A pdf or other document
 - `other` -- Any other file

If the `<type>` is not specified it is autodetected before the `<typespecific>` rules are applied.

The meaning of `<type-specific>` depends on `<type>`.

`<filter>` is a shell command that the content is piped through.

Compatibility notes!
 - Only `text` is supported in MAIA for OpenAI Chat Completions API.
 - `image` is only supported for [some models with AWS Bedrock Converse API](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_ToolResultContentBlock.html).

### Text files

Syntax:

```
<filepath>:text[:<selector>][|<filter>]
<filepath>[:<selector>][|<filter>]
```

`<selector>` is one of
* `<lineselector>` where it is formed as `<linestart>[-<lineend>]`
* [<language>:][<matchtype>:]<string>
* full

`<language>` is one of: `bash`, `c`, `php` and `python`, if not specified it is autodetected.
`<matchtype>` is `function`, if omitted it defaults to function. Only one match type is supported at the moment.

If `<selector>` is not specified the full file is selected.

Examples:

```
path/to/some-file.sh
some-file.sh
some-file.sh:0-5
some-file.sh:text
some-file.sh:main
some-file.sh:c:main
some-file.sh:c:function:main
some-file.sh:text:main
some-file.sh:text:c:function:main
lib/change.sh:change_usage
lib/change.sh:bash:function:change_usage
lib/change.sh:text:bash:function:change_usage
lib/change.sh:100-120
lib/change.sh:text:100-120
lib/change.sh:full
```


### Image files (`image`)

Syntax:

```
<path>[:image[:<resolution>]][|<filter>]
<path>[:<resolution>][|<filter>]
<name/path>[:<resolution>]@<url>
```

`<resolution>` is one of: low, medium, high

'<url>' is an url that the AI API provider can use

Examples:
```
niceimage.gif
niceimage.gif:image
niceimage.png:image:high
```

## Document files (`document`)

Syntax:

```
<filepath>[:document[:<resolution>]][|<filter>]
<filepath>[:<resolution>][|<filter>]
<filename>[:<resolution>]@<url>
```

`<resolution>` is one of: low, medium, high

Examples:
```
document.pdf
document.pdf:document
document.pdf:document:high
```

## Other files (`other`)

Syntax:

```
<filepath>[:other][|<filter>]
```

'<url>' is an url that the AI API provider can use


Examples:

```
bin/ls
bin/ls:other
maia-1.0.0.tar.gz:other
```
