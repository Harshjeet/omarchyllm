/**
 * OmarchyLLM Tool Calling Manager
 * Defines system tools (run_command, read_file, write_file, list_dir, web_search, edit_memory, load_skill),
 * OpenAPI/JSON schema specifications, and command execution builders.
 */

var TOOL_DEFINITIONS = [
  {
    type: "function",
    function: {
      name: "run_command",
      description: "Execute a shell command in bash on the user's Linux system and return stdout/stderr. Prefer specific tools like read_file or list_dir when applicable.",
      parameters: {
        type: "object",
        properties: {
          justification: {
            type: "string",
            description: "A brief 1-sentence explanation of why this command is being run."
          },
          command: {
            type: "string",
            description: "The bash command to execute."
          }
        },
        required: ["justification", "command"]
      }
    }
  },
  {
    type: "function",
    function: {
      name: "read_file",
      description: "Read the contents of a local file. Output is capped at 200 KB to avoid context overflow.",
      parameters: {
        type: "object",
        properties: {
          justification: {
            type: "string",
            description: "A brief 1-sentence explanation of why this file is being read."
          },
          path: {
            type: "string",
            description: "The absolute or home-relative path to the file."
          }
        },
        required: ["justification", "path"]
      }
    }
  },
  {
    type: "function",
    function: {
      name: "write_file",
      description: "Write content to a local file. Parent directories are created automatically and writes are atomic.",
      parameters: {
        type: "object",
        properties: {
          justification: {
            type: "string",
            description: "A brief 1-sentence explanation of why this file is being written."
          },
          path: {
            type: "string",
            description: "The absolute or home-relative path to the target file."
          },
          content: {
            type: "string",
            description: "The full text content to write into the file."
          }
        },
        required: ["justification", "path", "content"]
      }
    }
  },
  {
    type: "function",
    function: {
      name: "list_dir",
      description: "List files and subdirectories inside a directory with file counts and directory headers.",
      parameters: {
        type: "object",
        properties: {
          justification: {
            type: "string",
            description: "A brief 1-sentence explanation of why this directory is being inspected."
          },
          path: {
            type: "string",
            description: "The path to the directory (e.g. '~' or '/home/harsh/Downloads')."
          }
        },
        required: ["justification", "path"]
      }
    }
  },
  {
    type: "function",
    function: {
      name: "web_search",
      description: "Search the web for real-time information, documentation, news, or facts. Returns search results with titles, URLs, and snippets.",
      parameters: {
        type: "object",
        properties: {
          justification: {
            type: "string",
            description: "A brief 1-sentence justification for why a web search is needed."
          },
          query: {
            type: "string",
            description: "The search query keywords."
          },
          max_results: {
            type: "integer",
            description: "Maximum number of results to retrieve (default: 5)."
          }
        },
        required: ["justification", "query"]
      }
    }
  },
  {
    type: "function",
    function: {
      name: "edit_memory",
      description: "Manage persistent long-term memories and user preferences remembered across all sessions. Use 'add' to save user habits, preferences, or technical requirements. Use 'list' to view, 'remove' to delete by 1-based index or matching text, and 'clear' to reset.",
      parameters: {
        type: "object",
        properties: {
          justification: {
            type: "string",
            description: "A brief 1-sentence explanation of why this memory action is being taken."
          },
          action: {
            type: "string",
            enum: ["add", "remove", "list", "clear"],
            description: "The memory action: 'add', 'remove', 'list', or 'clear'."
          },
          phrase: {
            type: "string",
            description: "The memory phrase to remember, or the 1-based index/phrase to remove. Not required for 'list' or 'clear'."
          }
        },
        required: ["justification", "action"]
      }
    }
  },
  {
    type: "function",
    function: {
      name: "load_skill",
      description: "Load detailed expert workflow instructions for a specialized domain skill by name. Check available skills before executing complex tasks.",
      parameters: {
        type: "object",
        properties: {
          justification: {
            type: "string",
            description: "A brief 1-sentence explanation of why this skill is being loaded."
          },
          name: {
            type: "string",
            description: "The skill name (e.g. 'arch-linux', 'hyprland')."
          }
        },
        required: ["justification", "name"]
      }
    }
  }
];

function getToolDefinitions(config) {
  if (!config) return TOOL_DEFINITIONS;
  if (config.toolsMasterEnabled === false) return [];

  var enabled = config.enabledTools || {};
  return TOOL_DEFINITIONS.filter(function(tool) {
    var name = tool.function.name;
    var key = name;
    if (name === "list_dir") key = "list_directory";
    if (name === "edit_memory") key = "save_memory";
    if (enabled[key] !== undefined) return enabled[key] === true;
    return true;
  });
}

function getToolDisplayName(name) {
  switch (name) {
    case "run_command": return "Run Shell Command";
    case "read_file": return "Read File";
    case "write_file": return "Write File";
    case "list_dir": return "List Directory";
    case "web_search": return "Web Search";
    case "edit_memory": return "Edit Memory";
    case "load_skill": return "Load Skill";
    default: return name;
  }
}

function getToolIcon(name) {
  switch (name) {
    case "run_command": return "󰆍";
    case "read_file": return "󰈔";
    case "write_file": return "󰈙";
    case "list_dir": return "󰉋";
    case "web_search": return "󰍉";
    case "edit_memory": return "󰘚";
    case "load_skill": return "󰦨";
    default: return "⚙";
  }
}

function parseToolArguments(rawArgs) {
  if (!rawArgs) return {};
  if (typeof rawArgs === "object") return rawArgs;
  if (typeof rawArgs === "string") {
    try {
      return JSON.parse(rawArgs);
    } catch (e) {
      console.warn("OmarchyLLM: Failed to parse tool arguments:", e);
      return { raw: rawArgs };
    }
  }
  return {};
}

function escapeShellArg(arg) {
  return "'" + String(arg || "").replace(/'/g, "'\\''") + "'";
}

/**
 * Builds the exact shell command string to execute for a tool invocation.
 */
function buildExecutionCommand(toolName, args) {
  args = args || {};

  switch (toolName) {
    case "run_command": {
      return args.command || "echo 'No command provided'";
    }

    case "read_file": {
      var maxBytes = 204800; // 200 KB max read
      var path = escapeShellArg(args.path);
      return "head -c " + maxBytes + " " + path;
    }

    case "write_file": {
      var targetPath = escapeShellArg(args.path);
      var content = args.content || "";
      var escapedContent = escapeShellArg(content);
      // Atomic write via temp file in parent dir
      return "tmpfile=$(mktemp) && printf %s " + escapedContent + " > \"$tmpfile\" && " +
             "mkdir -p $(dirname " + targetPath + ") && mv \"$tmpfile\" " + targetPath + " && " +
             "echo 'Successfully wrote " + content.length + " bytes to ' " + targetPath;
    }

    case "list_dir": {
      var dirPath = escapeShellArg(args.path || ".");
      return "path=" + dirPath + "; " +
             "count=$(ls -1A \"$path\" 2>/dev/null | wc -l); " +
             "printf 'Total items: %d\\n---\\n' \"$count\"; " +
             "ls -1A \"$path\" 2>/dev/null | head -n 250; " +
             "if [ \"$count\" -gt 250 ]; then printf '... and %d more items\\n' \"$((count - 250))\"; fi";
    }

    case "web_search": {
      var q = escapeShellArg(args.query || "");
      var max = parseInt(args.max_results || 5, 10);
      return "python3 $HOME/.config/omarchy/plugins/harsh.llm/search.py --query " + q + " --max " + max;
    }

    case "edit_memory": {
      var action = escapeShellArg(args.action || "list");
      var phrase = args.phrase ? escapeShellArg(args.phrase) : "''";
      return "python3 $HOME/.config/omarchy/plugins/harsh.llm/memory.py " + action + " " + phrase;
    }

    case "load_skill": {
      var skillName = escapeShellArg(args.name || "");
      return "python3 $HOME/.config/omarchy/plugins/harsh.llm/skill.py load " + skillName;
    }

    default:
      return "echo 'Unknown tool: " + toolName + "'";
  }
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    TOOL_DEFINITIONS,
    getToolDefinitions,
    getToolDisplayName,
    getToolIcon,
    parseToolArguments,
    buildExecutionCommand
  };
}
