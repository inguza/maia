[
  {
    "name": "cust-chain-a",
    "tool-dependencies": ["cust-chain-b"],
    "description": "Dependency-chain test tool A.",
    "command": "cust-placeholder",
    "inputSchema": {"type": "object", "properties": {}, "required": [], "additionalProperties": false}
  },
  {
    "name": "cust-chain-b",
    "tool-dependencies": ["cust-chain-c"],
    "description": "Dependency-chain test tool B.",
    "command": "cust-placeholder",
    "inputSchema": {"type": "object", "properties": {}, "required": [], "additionalProperties": false}
  },
  {
    "name": "cust-chain-c",
    "tool-dependencies": ["cust-chain-e"],
    "description": "Dependency-chain test tool C.",
    "command": "cust-placeholder",
    "inputSchema": {"type": "object", "properties": {}, "required": [], "additionalProperties": false}
  },
  {
    "name": "cust-chain-e",
    "description": "Dependency-chain test tool E.",
    "command": "cust-placeholder",
    "inputSchema": {"type": "object", "properties": {}, "required": [], "additionalProperties": false}
  }
]
