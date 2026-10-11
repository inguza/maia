[
  {
    "name": "openai-image-generate",
    "api_def": {
      "type": "image_generation"
    },
    "callback": "image_generation_call",
    "command": "openai-image-generation.sh",
    "effects": ["cost"]
  },
  {
    "name": "openai-web-text-search",
    "api_def": {
      "type": "web_search"
    },
    "callback": "web_search_call",
    "command": "openai-web-search.sh",
    "effects": ["cost"]
  },
  {
    "name": "openai-web-image-search",
    "api_def": {
      "type": "web_search",
      "search_content_types": ["text", "image"]
    },
    "callback": "web_search_call",
    "command": "openai-web-search.sh",
    "effects": ["cost"]
  }
]
