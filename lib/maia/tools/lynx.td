[
  {
    "name":"web-browser-lynx",
    "description": "Retrieve and browse a web page using Lynx. Returns the page content as text.",
    "command": "lynx.sh -accept_all_cookies -center -force_secure -list_decoded -list_inline -listonly -mime_header -nolist -nonumbers -noredir -nostatus -notitle -reload -short_url -source",
    "parameters": {
      "type": "object",
      "properties": {
        "url": {
          "type": "string",
          "description": "The url to browse"
        },
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of file command line arguments. Allowed are: -accept_all_cookies -center -force_secure -list_decoded -list_inline -listonly -mime_header -nolist -nonumbers -noredir -nostatus -notitle -reload -short_url -source."
	}
      },
      "required": ["url"]
    },
    "strict": true
  },
  {
    "name":"web-search-lynx",
    "description": "Search the web using Lynx and return the search results as text.",
    "command": "lynx.sh -accept_all_cookies -center -force_secure -list_decoded -list_inline -listonly -nonumbers -nostatus -notitle -reload -short_url",
    "parameters": {
      "type": "object",
      "properties": {
        "query": {
          "type": "string",
          "description": "The search string."
        },
	"arguments": {
	  "type": "array",
	  "items": {
	    "type": "string"
	  },
	  "description": "List of file command line arguments. Allowed are: -accept_all_cookies -center -force_secure -list_decoded -list_inline -listonly -nonumbers -nostatus -notitle -reload -short_url."
	}
      },
      "required": ["query"]
    },
    "strict": true
  }
]
