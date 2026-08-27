( (map(select(.role=="assistant" and any(.tool_calls[]?; .id == $source))) | .[0] | "\(.timestamp)-\(.id)") // "" ) as $prune_id
| map(
    if (.role == "assistant" and any(.tool_calls[]?; .id == $source)) then
        # Preserve the original state unless already backed up.
        (if has("backup") | not then
            .backup = (
                {}
                + (if has("content") then {content: .content} else {} end)
                + (if has("tool_calls") then {tool_calls: .tool_calls} else {} end)
            )
        else
            .
        end)
        |
        .tool_calls |= map(
            if .id == $source then
                .function.arguments = "<<Pruned>>"
            else
                .
            end
        )
        |
        # Only add original-reference marker if we could compute one
        if $prune_id == "" then
            .
        else
            if (.content // "") | contains("<<Original text reference:") then
                .
            else
                .content = (
                    if .content == null or .content == "" then "<<Original text reference: \($prune_id)>>" else .content + "\n<<Original text reference: \($prune_id)>>" end
                )
            end
        end
    else
        .
    end
)
