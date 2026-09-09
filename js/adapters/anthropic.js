.pragma library

// Anthropic Claude Adapter for Omarchy LLM
// Direct connection to https://api.anthropic.com/v1/messages

function buildHeaders(apiKey, endpoint, opts) {
  var headers = {
    "Content-Type": "application/json",
    "anthropic-version": "2023-06-01",
    "anthropic-dangerous-direct-browser-access": "true"
  };

  if (apiKey && apiKey.trim().length > 0) {
    headers["x-api-key"] = apiKey.trim();
  }

  return headers;
}

function buildRequestBody(model, messages, systemPrompt, opts) {
  opts = opts || {};
  var payloadMessages = [];

  for (var i = 0; i < messages.length; i++) {
    var m = messages[i];
    if (!m.role || !m.content || m.role === "system") continue;
    payloadMessages.push({
      role: m.role,
      content: m.content
    });
  }

  var body = {
    model: model || "claude-3-5-sonnet-20241022",
    messages: payloadMessages,
    stream: true,
    max_tokens: opts.maxTokens || 4096,
    temperature: (opts.temperature !== undefined) ? opts.temperature : 0.7
  };

  if (systemPrompt && systemPrompt.trim().length > 0) {
    body.system = systemPrompt.trim();
  }

  return body;
}

function parseSSEChunks(buffer, lastIndex) {
  var tokens = [];
  var searchFrom = lastIndex;

  while (true) {
    var nlPos = buffer.indexOf("\n", searchFrom);
    if (nlPos === -1) break;

    var line = buffer.substring(searchFrom, nlPos).replace(/\r$/, "").trim();
    searchFrom = nlPos + 1;

    if (line === "" || line.indexOf(":") === 0) continue;

    if (line.indexOf("data: ") === 0) {
      var payload = line.substring(6).trim();

      if (payload === "[DONE]") {
        tokens.push({ done: true });
        continue;
      }

      try {
        var data = JSON.parse(payload);
        if (data.type === "content_block_delta" && data.delta) {
          if (data.delta.type === "text_delta" && typeof data.delta.text === "string") {
            tokens.push({ content: data.delta.text });
          } else if (data.delta.type === "thinking_delta" && typeof data.delta.thinking === "string") {
            tokens.push({ thinking_delta: data.delta.thinking });
          }
        } else if (data.type === "message_stop") {
          tokens.push({ done: true });
        }
      } catch (e) {}
    }
  }

  return { tokens: tokens, newIndex: searchFrom };
}
