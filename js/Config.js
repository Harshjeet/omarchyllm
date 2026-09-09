.pragma library

// Configuration & Profiles Engine for Omarchy LLM

var PROVIDERS = [
  {
    id: "ollama",
    displayName: "Ollama (Local)",
    defaultEndpoint: "http://localhost:11434/v1",
    requiresKey: false,
    keyPlaceholder: "None needed (local service)",
    description: "Run open-source models completely locally on your machine",
    defaultModels: ["llama3.2", "qwen2.5-coder", "mistral", "deepseek-r1:8b", "phi3"]
  },
  {
    id: "lmstudio",
    displayName: "LM Studio (Local)",
    defaultEndpoint: "http://localhost:1234/v1",
    requiresKey: false,
    keyPlaceholder: "None needed (local service)",
    description: "Connect to LM Studio local server",
    defaultModels: ["local-model"]
  },
  {
    id: "openrouter",
    displayName: "OpenRouter",
    defaultEndpoint: "https://openrouter.ai/api/v1",
    requiresKey: true,
    keyPlaceholder: "sk-or-v1-...",
    description: "Access any open or proprietary model through one unified API",
    defaultModels: [
      "nvidia/nemotron-3.5-lightning:free",
      "liquid/lfm-2.5-2.6b:free",
      "nex-agi/nex-n2.5-mini:free",
      "inclusionai/ling-3.0-flash-fin:free",
      "nvidia/nemotron-3-super-120b-a12b:free",
      "anthropic/claude-3.7-sonnet",
      "openai/gpt-4o",
      "deepseek/deepseek-r1"
    ]
  },
  {
    id: "openai",
    displayName: "OpenAI",
    defaultEndpoint: "https://api.openai.com/v1",
    requiresKey: true,
    keyPlaceholder: "sk-proj-...",
    description: "Official OpenAI models (GPT-4o, o1, o3-mini)",
    defaultModels: ["gpt-4o", "gpt-4o-mini", "o3-mini", "o1"]
  },
  {
    id: "anthropic",
    displayName: "Anthropic Claude",
    defaultEndpoint: "https://api.anthropic.com/v1",
    requiresKey: true,
    keyPlaceholder: "sk-ant-api03-...",
    description: "Official Claude models with advanced reasoning and coding",
    defaultModels: [
      "claude-3-7-sonnet-20250219",
      "claude-3-5-sonnet-20241022",
      "claude-3-5-haiku-20241022"
    ]
  },
  {
    id: "gemini",
    displayName: "Google Gemini",
    defaultEndpoint: "https://generativelanguage.googleapis.com/v1beta/openai",
    requiresKey: true,
    keyPlaceholder: "AIzaSy...",
    description: "Google Gemini API with massive context and fast inference",
    defaultModels: [
      "gemini-2.0-flash",
      "gemini-1.5-pro",
      "gemini-1.5-flash"
    ]
  },
  {
    id: "groq",
    displayName: "Groq (Free & Fast + Whisper)",
    defaultEndpoint: "https://api.groq.com/openai/v1",
    requiresKey: true,
    keyPlaceholder: "gsk_...",
    description: "Ultra-fast inference and free Whisper speech-to-text API (console.groq.com)",
    defaultModels: [
      "llama-3.3-70b-versatile",
      "llama-3.1-8b-instant",
      "mixtral-8x7b-32768",
      "gemma2-9b-it"
    ]
  },
  {
    id: "custom",
    displayName: "Custom OpenAI-Compatible",
    defaultEndpoint: "http://localhost:8080/v1",
    requiresKey: false,
    keyPlaceholder: "Optional API Key",
    description: "Any self-hosted or proxy endpoint supporting /v1/chat/completions",
    defaultModels: ["custom-model"]
  }
];

var DEFAULT_SYSTEM_PROMPT = "You are OmarchyLLM, a helpful and efficient AI assistant embedded directly into the user's Omarchy Linux desktop (Hyprland + Quickshell).\n" +
  "\n" +
  "## System\n" +
  "{{system_info}}\n" +
  "\n" +
  "General-purpose desktop assistant. Keep responses short and concise (~1 paragraph) unless the user asks for more detail. " +
  "When providing terminal commands, recommend Arch Linux / Hyprland tools (`pacman`, `yay`, `hyprctl`, `systemctl`). " +
  "Always refer to the user's home directory as `~`.\n" +
  "\n" +
  "{{memories}}";

var DEFAULT_CONFIG = {
  activeProvider: "openrouter",
  activeModel: "nvidia/nemotron-3.5-lightning:free",
  temperature: 0.7,
  maxTokens: 4096,
  topP: 1.0,
  showThoughts: true,
  systemPrompt: DEFAULT_SYSTEM_PROMPT,
  toolsMasterEnabled: true,
  enabledTools: {
    run_command: true,
    read_file: true,
    write_file: true,
    edit_file: true,
    list_directory: true,
    web_search: true,
    save_memory: true
  },
  autoApproveTerminal: false,
  autoApproveTools: false,
  workspaceDir: "~",
  enableWebSearch: true,
  webSearchProvider: "duckduckgo",
  maxSearchResults: 5,
  compactionEnabled: true,
  compactionTriggerMode: "chars",
  compactionThresholdChars: 20000,
  compactionThresholdTurns: 4,
  compactionKeepRecentTurns: 4,
  compactionInstructions:
    "Summarize this conversation. Be very concise and use shorthand and abbreviations when possible. No prose. Retain important specifics when brief. Cite every item with a msgId or msgId range, e.g. [1], [3-6].\n\n" +
    "When a previous compaction exists, use it as a starting point. Be conservative about removing things; update and merge new information rather than discarding established context.\n\n" +
    "Structure:\n" +
    "# Key Topics\n<...>\n" +
    "# User Goals\n<...>\n" +
    "# Decisions & Code Changes\n<...>\n" +
    "# Current Status\n<...>",
  sttEnabled: true,
  sttBackend: "whisper",
  sysInfoOS: true,
  sysInfoKernel: true,
  sysInfoShell: true,
  sysInfoCPU: true,
  sysInfoMemory: true,
  sysInfoGPU: true,
  sysInfoDateTime: true,
  providerModels: {},
  endpoints: {
    ollama: "http://localhost:11434/v1",
    lmstudio: "http://localhost:1234/v1",
    openrouter: "https://openrouter.ai/api/v1",
    openai: "https://api.openai.com/v1",
    anthropic: "https://api.anthropic.com/v1",
    gemini: "https://generativelanguage.googleapis.com/v1beta/openai",
    groq: "https://api.groq.com/openai/v1",
    custom: "http://localhost:8080/v1"
  }
};

function getProviders() {
  return PROVIDERS;
}

function getProvider(id) {
  for (var i = 0; i < PROVIDERS.length; i++) {
    if (PROVIDERS[i].id === id) return PROVIDERS[i];
  }
  return PROVIDERS[0];
}

function parseConfigFile(rawText) {
  if (!rawText || typeof rawText !== "string" || rawText.trim() === "") {
    return JSON.parse(JSON.stringify(DEFAULT_CONFIG));
  }
  try {
    var parsed = JSON.parse(rawText);
    var merged = JSON.parse(JSON.stringify(DEFAULT_CONFIG));
    for (var k in parsed) {
      if (parsed.hasOwnProperty(k)) {
        if (typeof parsed[k] === "object" && parsed[k] !== null && !Array.isArray(parsed[k]) && typeof merged[k] === "object" && merged[k] !== null && !Array.isArray(merged[k])) {
          for (var subK in parsed[k]) {
            if (parsed[k].hasOwnProperty(subK)) {
              merged[k][subK] = parsed[k][subK];
            }
          }
        } else {
          merged[k] = parsed[k];
        }
      }
    }
    return merged;
  } catch (e) {
    console.warn("OmarchyLLM: Failed to parse config.json, using defaults:", e);
    return JSON.parse(JSON.stringify(DEFAULT_CONFIG));
  }
}

function parseKeysFile(rawText) {
  if (!rawText || typeof rawText !== "string" || rawText.trim() === "") {
    return {};
  }
  try {
    return JSON.parse(rawText);
  } catch (e) {
    console.warn("OmarchyLLM: Failed to parse keys.json:", e);
    return {};
  }
}

function maskApiKey(key) {
  if (!key || typeof key !== "string" || key.length < 8) return "";
  return key.slice(0, 4) + "••••••••" + key.slice(-4);
}
