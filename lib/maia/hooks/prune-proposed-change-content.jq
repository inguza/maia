            map(
                if (
                    (.role == "tool" and .tool_call_id == $source)
                    or
                    (.role == "assistant"
                     and any(.tool_calls[]?; .id == $source))
                )
                then
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

		    if .role == "tool" then
		      if (.content | index("The content of the proposed change is the following:\n")) != null then
		          .content |= (
			     . as $content
			     | ("The content of the proposed change is the following:\n") as $marker
			     | ($content | index($marker)) as $pos
			     | ($pos + ($marker | length)) as $start
			     | ($content[0:$start]
			        + "<<Pruned>>\n<<Original text reference: \($prune_id)>>")
			 )
		      else
		        .
		      end

                    elif .role == "assistant" then
                        .tool_calls |= map(
                            if .id == $source then
                                .function.arguments = "<<Pruned>>"
                            else
                                .
                            end
                        )
                        | if (.content // "") | contains("<<Original text reference:")
			  then .
			  else
			    .content = (
			      if .content == null or .content == ""
                              then "<<Original text reference: \($prune_id)>>"
                              else .content + "\n<<Original text reference: \($prune_id)>>"
                              end
			    )
                          end
                    else
                        .
                    end
                else
                    .
                end
            )
