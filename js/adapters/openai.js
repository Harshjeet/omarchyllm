.pragma library

// OpenAI-Compatible Adapter for Omarchy LLM
// Supports: Ollama, LM Studio, OpenRouter, OpenAI, Groq, DeepSeek, Gemini (OpenAI endpoint)

function buildHeaders(apiKey, endpoint, opts) {
  var headers = {
    "Content-Type": "application/json"
  };

  if (apiKey && apiKey.trim().length > 0) {
    headers["Authorization"] = "Bearer " + apiKey.trim();
  }

  // OpenRouter session / app identification
  if (endpoint && endpoint.indexOf("openrouter.ai") !== -1) {
    headers["HTTP-Referer"] = "https://github.com/omarchy";
    headers["X-Title"] = "Omarchy LLM";
  }

  return headers;
}

function buildRequestBody(model, messages, systemPrompt, opts) {
  opts = opts || {};
  var payloadMessages = [];

  // Add system prompt if provided
  if (systemPrompt && systemPrompt.trim().length > 0) {
    payloadMessages.push({
      role: "system",
      content: systemPrompt.trim()
    });
  }

  // Append conversation history
  for (var i = 0; i < messages.length; i++) {
    var m = messages[i];
    if (!m || !m.role) continue;

    if (m.role === "tool") {
      payloadMessages.push({
        role: "tool",
        tool_call_id: m.tool_call_id || "",
        content: String(m.content !== undefined && m.content !== null ? m.content : "")
      });
    } else if (m.role === "assistant") {
      var asstMsg = {
        role: "assistant",
        content: m.content !== undefined && m.content !== null ? String(m.content) : ""
      };
      if (m.tool_calls && Array.isArray(m.tool_calls) && m.tool_calls.length > 0) {
        asstMsg.tool_calls = m.tool_calls;
      }
      payloadMessages.push(asstMsg);
    } else {
      if (m.content !== undefined && m.content !== null) {
        payloadMessages.push({
          role: m.role,
          content: String(m.content)
        });
      }
    }
  }

  var body = {
    model: model || "llama3.2",
    messages: payloadMessages,
    stream: true,
    temperature: (opts.temperature !== undefined) ? opts.temperature : 0.7,
    max_tokens: opts.maxTokens || 4096
  };

  // Optional tools schema if provided
  if (opts.tools && Array.isArray(opts.tools) && opts.tools.length > 0) {
    body.tools = opts.tools;
  }

  return body;
}

function parseSSEChunks(buffer, lastIndex) {
  var tokens = [];
  var searchFrom = lastIndex;

  while (true) {
    var nlPos = buffer.indexOf("\n", searchFrom);
    if (nlPos === -1) break; // Partial line, wait for next network packet

    var line = buffer.substring(searchFrom, nlPos).replace(/\r$/, "").trim();
    searchFrom = nlPos + 1;

    if (line === "" || line.indexOf(":") === 0) continue; // Keep-alive comment or empty line

    if (line.indexOf("data: ") === 0) {
      var payload = line.substring(6).trim();

      if (payload === "[DONE]") {
        tokens.push({ done: true });
        continue;
      }

      try {
        var data = JSON.parse(payload);

        // Catch in-stream error payloads emitted by OpenRouter/OpenAI
        if (data.error) {
          var errMessage = data.error.message || (typeof data.error === "string" ? data.error : JSON.stringify(data.error));
          tokens.push({ error: errMessage });
          continue;
        }

        if (data.choices && data.choices[0]) {
          var choice = data.choices[0];
          var delta = choice.delta;

          if (delta) {
            // Standard content delta
            if (typeof delta.content === "string" && delta.content.length > 0) {
              tokens.push({ content: delta.content });
            }

            // Reasoning tokens (DeepSeek-R1, Qwen reasoning, o-series, Nemotron reasoning)
            if (typeof delta.reasoning_content === "string" && delta.reasoning_content.length > 0) {
              tokens.push({ thinking_delta: delta.reasoning_content });
            } else if (typeof delta.reasoning === "string" && delta.reasoning.length > 0) {
              tokens.push({ thinking_delta: delta.reasoning });
            }

            // Function call / Tool calls delta
            if (delta.tool_calls) {
              tokens.push({ tool_calls_delta: delta.tool_calls });
            }
          } else if (choice.message) {
            // Some providers/proxies send non-delta full messages in the stream
            if (typeof choice.message.content === "string" && choice.message.content.length > 0) {
              tokens.push({ content: choice.message.content });
            }
            if (choice.message.tool_calls) {
              tokens.push({ tool_calls_delta: choice.message.tool_calls });
            }
          } else if (typeof choice.text === "string" && choice.text.length > 0) {
            // Completion format fallback
            tokens.push({ content: choice.text });
          }
        }
      } catch (e) {
        // Incomplete JSON chunk, skip
      }
    }
  }

  return { tokens: tokens, newIndex: searchFrom };
}

