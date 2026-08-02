`nimo chat`
`nimo session list`
`mkdir -r ~/.ws/temp5 && nimo chat -w ~/.ws/temp5`
`nimo chat -w .` // Default
`nimo demo intent "I want to create a story"`
```txt
System: You are a helpful assistant. Figure out what the user's intention is.
<status>{
workspace: {
    path: "/home/alex/.ws/temp5",
    stories: [],
    plans: [],
    goals: []
},
user: {
    name: "Alex",
    email: "alex@nimo.ai"
}
}</status>
<tools>{
    "create_story": {
        "description": "Create a story",
        "parameters": {
            "type": "object",
            "properties": {
                "story_type": {
                    "type": "string",
                    "description": "The type of story to create"
                }
            },
            "required": []
        }
    },
    {
    "examine_workspace": {
        "description": "Examine the workspace",
        "parameters": {
            "type": "object",
            "properties": {
                "workspace": {
                    "type": "string",
                    "description": "The workspace to examine"
                }
            },
            "required": []
        }
    },
    "create_plan": {
        "description": "Create a plan",
        "parameters": {
            "type": "object",
            "properties": {
                "plan": {
                    "type": "string",
                    "description": "The plan to create"
                }
            },
            "required": []
        }
    },
    "create_goal": {
        "description": "Create a goal",
        "parameters": {
            "type": "object",
            "properties": {
                "goal": {
                    "type": "string",
                    "description": "The goal to create"
                }
            },
            "required": []
        }
    }
}
</tools>

User: I want to create a story

Assistant: <think></think><tool_call>[
{"create_story": {}}
]</tool_call>
```

`nimo demo intent "I tell me about this workspace, then write a summary about it to to workspace-summary.md"`
```txt
System: You are a helpful assistant. Figure out what the user's intention is.
<status>{
workspace: {
    path: "/home/alex/.ws/temp5",
    stories: [],
    plans: [],
    goals: []
},
user: {
    name: "Alex",
    email: "alex@nimo.ai"
}
}</status>
<tools>{
    "examine_workspace": {
        "description": "Examine the workspace",
        "parameters": {
            "type": "object",
            "properties": {
                "workspace": {
                    "type": "string",
                    "description": "The workspace to examine"
                }
            },
            "required": []
        }
    },
    "create_story": {
        "description": "Create a story",
        "parameters": {
            "type": "object",
            "properties": {
                "story_type": {
                    "type": "string",
                    "description": "The type of story to create"
                }
            },
            "required": []
        }
    },
    "write_file":{
        "description": "Write a file",
        "parameters": {
            "type": "object",
            "properties": {
                "file_name": {
                    "type": "string",
                    "description": "The name of the file to write"
                },
                "content": {
                    "type": "string",
                    "description": "The content of the file to write"
                }
            },
            "required": []
        }
    }
    "create_plan": {
        "description": "Create a plan",
        "parameters": {
            "type": "object",
            "properties": {
                "plan": {
                    "type": "string",
                    "description": "The plan to create"
                }
            },
            "required": []
        }
    },
    "create_goal": {
        "description": "Create a goal",
        "parameters": {
            "type": "object",
            "properties": {
                "goal": {
                    "type": "string",
                    "description": "The goal to create"
                }
            },
            "required": []
        }
    }
}
</tools>

User: I tell me about this workspace, then write a summary about it to to workspace-summary.md

Assistant: 
<tool_call>[
{"examine_workspace": {"workspace": "/home/alex/.ws/temp5"}},
{"write_file": {"file_name": "workspace-summary.md", "content": "This is a summary of the workspace."}}
]
```
