[
  {
    "name": "cust-exec-chain-a",
    "tool-dependencies": ["cust-exec-chain-b"],
    "description": "Executable dependency-chain test tool A.",
    "command": "cust-placeholder",
    "inputSchema": {"type": "object", "properties": {}, "required": [], "additionalProperties": false}
  },
  {
    "name": "cust-exec-chain-b",
    "tool-dependencies": ["cust-exec-chain-c"],
    "description": "Executable dependency-chain test tool B.",
    "command": "cust-placeholder",
    "inputSchema": {"type": "object", "properties": {}, "required": [], "additionalProperties": false}
  },
  {
    "name": "cust-exec-chain-c",
    "tool-dependencies": ["cust-exec-chain-e"],
    "description": "Executable dependency-chain test tool C.",
    "command": "cust-placeholder",
    "inputSchema": {"type": "object", "properties": {}, "required": [], "additionalProperties": false}
  },
  {
    "name": "cust-exec-chain-e",
    "exec-dependencies": ["xcusdkjfd"],
    "description": "Executable dependency-chain test tool E.",
    "command": "cust-placeholder",
    "inputSchema": {"type": "object", "properties": {}, "required": [], "additionalProperties": false}
  }
]
