.pragma library

// Core Network Dispatcher & Streaming Engine for Omarchy LLM
.import "adapters/openai.js" as OpenAI
.import "adapters/anthropic.js" as Anthropic

function getAdapter(providerId) {
  if (providerId === "anthropic") {
    return Anthropic;
  }
  return OpenAI;
}

function resolveUrl(endpoint, providerId) {
  var base = (endpoint || "http://localhost:11434/v1").replace(/\/+$/, "");

  if (providerId === "anthropic") {
    if (base.indexOf("/messages") === -1) {
      return base + "/messages";
    }
    return base;
  }

  // OpenAI-compatible endpoint
  if (base.indexOf("/chat/completions") === -1) {
    return base + "/chat/completions";
  }
  return base;
}

function sendChatStream(options) {
  var endpoint = options.endpoint;
  var apiKey = options.apiKey || "";
  var providerId = options.providerId || "ollama";
  var model = options.model || "llama3.2";
  var messages = options.messages || [];
  var systemPrompt = options.systemPrompt || "";

  var onChunk = options.onChunk || function() {};
  var onThinkingChunk = options.onThinkingChunk || function() {};
  var onComplete = options.onComplete || function() {};
  var onError = options.onError || function() {};

  var adapter = getAdapter(providerId);
  var targetUrl = resolveUrl(endpoint, providerId);
  console.log("OmarchyLLM: Api.sendChatStream POST to:", targetUrl, "model:", model);

  var xhr = new XMLHttpRequest();
  xhr.open("POST", targetUrl, true);
  xhr.timeout = 45000; // 45 seconds

  var headers = adapter.buildHeaders(apiKey, endpoint, options);
  for (var h in headers) {
    if (headers.hasOwnProperty(h)) {
      xhr.setRequestHeader(h, headers[h]);
    }
  }

  var lastParseIndex = 0;
  var accumulatedText = "";
  var accumulatedThinking = "";
  var accumulatedToolCalls = [];
  var isDone = false;
  var hasTerminated = false;

  function finishSuccess() {
    if (hasTerminated) return;
    hasTerminated = true;
    console.log("OmarchyLLM: Api.finishSuccess completed with text length:", accumulatedText.length);
    onComplete(accumulatedText, accumulatedThinking, accumulatedToolCalls);
  }

  function finishError(err) {
    if (hasTerminated) return;
    hasTerminated = true;
    console.warn("OmarchyLLM: Api.finishError:", err);
    onError(err);
  }

  function processIncoming() {
    var response = xhr.responseText;
    if (!response || response.length <= lastParseIndex) return;

    var result = adapter.parseSSEChunks(response, lastParseIndex);
    lastParseIndex = result.newIndex;

    for (var i = 0; i < result.tokens.length; i++) {
      var tok = result.tokens[i];

      // Handle in-stream error emitted by provider
      if (tok.error) {
        finishError(tok.error);
        return;
      }

      if (tok.done) {
        isDone = true;
        continue;
      }

      if (tok.content) {
        accumulatedText += tok.content;
        onChunk(tok.content, accumulatedText);
      }

      if (tok.thinking_delta) {
        accumulatedThinking += tok.thinking_delta;
        onThinkingChunk(tok.thinking_delta, accumulatedThinking);
      }

      if (tok.tool_calls_delta) {
        for (var t = 0; t < tok.tool_calls_delta.length; t++) {
          var delta = tok.tool_calls_delta[t];
          var idx = delta.index !== undefined ? delta.index : 0;

          if (!accumulatedToolCalls[idx]) {
            accumulatedToolCalls[idx] = {
              id: delta.id || ("call_" + Math.random().toString(36).substring(2, 10)),
              type: delta.type || "function",
              "function": { name: "", arguments: "" }
            };
          }

          if (delta.id) accumulatedToolCalls[idx].id = delta.id;
          if (delta["function"]) {
            if (delta["function"].name) accumulatedToolCalls[idx]["function"].name += delta["function"].name;
            if (delta["function"].arguments) {
              accumulatedToolCalls[idx]["function"].arguments += delta["function"].arguments;
            }
          }
        }
      }
    }
  }

  xhr.onreadystatechange = function() {
    if (xhr.readyState === 3 || xhr.readyState === 4) {
      processIncoming();
    }

    if (xhr.readyState === 4) {
      if (xhr.status >= 200 && xhr.status < 300) {
        processIncoming();

        // Non-streaming fallback if no tokens were emitted during SSE
        if (accumulatedText.length === 0 && accumulatedToolCalls.length === 0) {
          try {
            var fullJson = JSON.parse(xhr.responseText);
            if (fullJson.error) {
              var em = fullJson.error.message || (typeof fullJson.error === "string" ? fullJson.error : JSON.stringify(fullJson.error));
              finishError(em);
              return;
            }
            if (fullJson.choices && fullJson.choices[0]) {
              var c = fullJson.choices[0];
              var msg = c.message || {};
              if (msg.content) {
                accumulatedText = msg.content;
                onChunk(msg.content, accumulatedText);
              }
              if (msg.reasoning_content || msg.reasoning) {
                accumulatedThinking = msg.reasoning_content || msg.reasoning;
                onThinkingChunk(accumulatedThinking, accumulatedThinking);
              }
              if (msg.tool_calls) {
                accumulatedToolCalls = msg.tool_calls;
              }
            }
          } catch(e) {}
        }

        if (accumulatedText.length === 0 && accumulatedToolCalls.length === 0 && accumulatedThinking.length === 0) {
          finishError("Model provider returned an empty response or timed out. Please choose another model.");
          return;
        }

        finishSuccess();
      } else if (xhr.status === 0) {
        // Network connection failure or abort
        if (!hasTerminated) {
          if (providerId === "ollama" && endpoint.indexOf("localhost") !== -1) {
            finishError("Could not connect to Ollama at " + endpoint + ". Is `ollama serve` running?");
          } else {
            finishError("Connection refused or network unavailable. Check endpoint URL.");
          }
        }
      } else {
        // HTTP Error status
        var errMsg = "HTTP " + xhr.status + " " + xhr.statusText;
        try {
          var errObj = JSON.parse(xhr.responseText);
          if (errObj.error && errObj.error.message) {
            errMsg = errObj.error.message;
          } else if (errObj.message) {
            errMsg = errObj.message;
          }
        } catch(e) {}

        if (xhr.status === 401) {
          errMsg = "Unauthorized (401): Invalid or missing API key for " + providerId + ". Check Settings.";
        } else if (xhr.status === 404) {
          errMsg = "Endpoint or model not found (404). Check model name: " + model;
        } else if (xhr.status === 429) {
          errMsg = "Rate limited or quota exceeded (429). The model is busy or your free credit quota is exhausted. Try a free model like nvidia/nemotron-3.5-lightning:free.";
        }

        finishError(errMsg);
      }
    }
  };

  xhr.ontimeout = function() {
    finishError("Request timed out after 45 seconds. The model host may be overloaded or offline.");
  };

  xhr.onerror = function() {
    if (providerId === "ollama" && endpoint.indexOf("localhost") !== -1) {
      finishError("Could not connect to Ollama at " + endpoint + ". Is `ollama serve` running?");
    } else {
      finishError("Network request failed. Check endpoint connection.");
    }
  };

  try {
    var reqBody = adapter.buildRequestBody(model, messages, systemPrompt, options);
    xhr.send(JSON.stringify(reqBody));
  } catch (err) {
    finishError("Failed to initiate request: " + (err.message || err));
  }

  return {
    abort: function() {
      hasTerminated = true;
      try { xhr.abort(); } catch(e) {}
    }
  };
}

function streamChatCompletion(providerId, providerOptions, messages, callbacks) {
  providerOptions = providerOptions || {};
  callbacks = callbacks || {};

  var opts = {
    providerId: providerId,
    endpoint: providerOptions.endpoint,
    apiKey: providerOptions.apiKey,
    model: providerOptions.model,
    messages: messages,
    systemPrompt: providerOptions.systemPrompt || "",
    temperature: providerOptions.temperature,
    maxTokens: providerOptions.maxTokens,
    tools: providerOptions.tools,
    onChunk: callbacks.onToken,
    onThinkingChunk: callbacks.onThinking,
    onComplete: callbacks.onDone,
    onError: callbacks.onError
  };

  return sendChatStream(opts);
}

function fetchModels(providerId, endpoint, apiKey, callback) {
  var url = "";
  var headers = {
    "Accept": "application/json"
  };

  var base = (endpoint || "").replace(/\/+$/, "");

  if (providerId === "openrouter") {
    url = "https://openrouter.ai/api/v1/models";
    if (apiKey && apiKey.trim().length > 0) {
      headers["Authorization"] = "Bearer " + apiKey.trim();
    }
    headers["HTTP-Referer"] = "https://github.com/omarchy";
    headers["X-Title"] = "Omarchy LLM";
  } else if (providerId === "ollama") {
    url = (base || "http://localhost:11434") + "/api/tags";
  } else if (providerId === "anthropic") {
    url = "https://api.anthropic.com/v1/models";
    if (apiKey && apiKey.trim().length > 0) {
      headers["x-api-key"] = apiKey.trim();
      headers["anthropic-version"] = "2023-06-01";
    }
  } else if (providerId === "gemini") {
    url = "https://generativelanguage.googleapis.com/v1beta/openai/models";
    if (apiKey && apiKey.trim().length > 0) {
      headers["Authorization"] = "Bearer " + apiKey.trim();
    }
  } else {
    url = (base || "https://api.openai.com/v1") + "/models";
    if (apiKey && apiKey.trim().length > 0) {
      headers["Authorization"] = "Bearer " + apiKey.trim();
    }
  }

  var xhr = new XMLHttpRequest();
  xhr.open("GET", url, true);
  xhr.timeout = 20000;

  for (var h in headers) {
    if (headers.hasOwnProperty(h)) {
      xhr.setRequestHeader(h, headers[h]);
    }
  }

  xhr.ontimeout = function() {
    callback("Request timed out after 20 seconds. Check network.", null);
  };

  xhr.onerror = function() {
    if (providerId === "ollama") {
      callback("Could not connect to Ollama at " + (base || "http://localhost:11434") + ". Is `ollama serve` running?", null);
    } else {
      callback("Network connection failed to " + url, null);
    }
  };

  xhr.onreadystatechange = function() {
    if (xhr.readyState === 4) {
      if (xhr.status >= 200 && xhr.status < 300) {
        try {
          var res = JSON.parse(xhr.responseText);
          var modelList = [];

          if (res.data && Array.isArray(res.data)) {
            for (var i = 0; i < res.data.length; i++) {
              var m = res.data[i];
              if (m && m.id) modelList.push(m.id);
            }
          } else if (res.models && Array.isArray(res.models)) {
            for (var j = 0; j < res.models.length; j++) {
              var om = res.models[j];
              if (om && (om.name || om.model)) modelList.push(om.name || om.model);
            }
          }

          if (providerId === "openrouter") {
            var priorityModels = [
              "nvidia/nemotron-3.5-lightning:free",
              "liquid/lfm-2.5-2.6b:free",
              "nex-agi/nex-n2.5-mini:free",
              "inclusionai/ling-3.0-flash-fin:free",
              "nvidia/nemotron-3-super-120b-a12b:free"
            ];
            modelList.sort(function(a, b) {
              var aPrio = priorityModels.indexOf(a);
              var bPrio = priorityModels.indexOf(b);
              if (aPrio !== -1 && bPrio !== -1) return aPrio - bPrio;
              if (aPrio !== -1) return -1;
              if (bPrio !== -1) return 1;

              var aFree = a.indexOf(":free") !== -1 ? 0 : 1;
              var bFree = b.indexOf(":free") !== -1 ? 0 : 1;
              if (aFree !== bFree) return aFree - bFree;
              return a.localeCompare(b);
            });
          } else {
            modelList.sort(function(a, b) {
              return a.localeCompare(b);
            });
          }

          callback(null, modelList);
        } catch(e) {
          callback("Failed to parse models response: " + e.message, null);
        }
      } else {
        var errText = "HTTP " + xhr.status + ": " + xhr.statusText;
        try {
          var errObj = JSON.parse(xhr.responseText);
          if (errObj.error && errObj.error.message) errText = errObj.error.message;
          else if (errObj.message) errText = errObj.message;
        } catch(e) {}
        callback(errText, null);
      }
    }
  };

  xhr.send();
}


