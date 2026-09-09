.pragma library

// Context Compactor for Omarchy LLM
// Summarizes earlier conversation turns into a cited context memory block
// when history exceeds threshold, preventing context window exhaustion.

.import "Api.js" as Api

/**
 * Calculates character count and finds candidate compaction slice
 * keeping the last `keepRecentTurns` full turns uncompacted.
 */
function findCompactionRange(chatModel, lastCompactedMsgId, keepRecentTurns) {
  if (!chatModel || chatModel.count <= 2) return null;

  var recentTurns = Math.max(1, keepRecentTurns || 4);

  // 1. Find start index
  var startIndex = 0;
  if (lastCompactedMsgId !== undefined && lastCompactedMsgId !== null && String(lastCompactedMsgId).trim().length > 0) {
    var parsed = parseInt(lastCompactedMsgId, 10);
    if (!isNaN(parsed) && parsed >= 0) {
      startIndex = parsed + 1;
    }
  }

  if (startIndex >= chatModel.count) return null;

  // 2. Identify the boundary of the last `keepRecentTurns` user turns
  var userTurnIndices = [];
  for (var j = 0; j < chatModel.count; j++) {
    var item = chatModel.get(j);
    if (item && item.role === "user") {
      userTurnIndices.push(j);
    }
  }

  var endIndex = -1;
  if (userTurnIndices.length > recentTurns) {
    var keepFromTurnIndex = userTurnIndices[userTurnIndices.length - recentTurns];
    endIndex = keepFromTurnIndex - 1;
  } else {
    // Not enough user turns to compact
    return null;
  }

  if (endIndex < startIndex) return null;

  // 3. Calculate total character count across the range
  var totalChars = 0;
  var candidateTurns = 0;
  for (var k = startIndex; k <= endIndex; k++) {
    var msg = chatModel.get(k);
    if (!msg) continue;
    if (msg.role === "user") candidateTurns++;
    if (msg.content) totalChars += String(msg.content).length;
    if (msg.stdoutText) totalChars += String(msg.stdoutText).length;
  }

  return {
    startIndex: startIndex,
    endIndex: endIndex,
    totalChars: totalChars,
    candidateTurns: candidateTurns,
    startMsgId: String(startIndex),
    endMsgId: String(endIndex)
  };
}

/**
 * Formats a slice of chat messages into a plain-text transcript with explicit message indices.
 */
function formatTranscript(chatModel, startIndex, endIndex) {
  var lines = [];
  for (var i = startIndex; i <= endIndex && i < chatModel.count; i++) {
    var m = chatModel.get(i);
    if (!m) continue;

    var time = m.timestamp || "";
    var header = "[" + i + "] Role: " + m.role + (time ? " (" + time + ")" : "");
    lines.push(header);

    if (m.role === "tool_result") {
      if (m.toolCallId) lines.push("Tool Call ID: " + m.toolCallId);
      lines.push("Tool: " + (m.toolName || "tool"));
      if (m.stdoutText) lines.push("Output:\n" + m.stdoutText);
      if (m.stderrText) lines.push("Error:\n" + m.stderrText);
    } else {
      if (m.content) lines.push("Content:\n" + m.content);
      if (m.thinking) lines.push("Thinking:\n" + m.thinking);
    }
    lines.push("");
  }
  return lines.join("\n");
}

/**
 * Asynchronously compacts history by sending a summarization prompt to the configured LLM.
 */
function compactHistory(providerId, providerOptions, transcript, previousSummary, callback) {
  if (!providerOptions || !providerOptions.endpoint || !providerOptions.model) {
    if (callback) callback("Compaction requires endpoint and model name", null);
    return;
  }

  var instructions = (
    "You are a compact summarizer for conversation history in a desktop AI assistant.\n" +
    "Summarize this conversation concisely. Retain specific facts, code snippets, file paths, and terminal commands when relevant.\n" +
    "Cite every key item with its message ID, e.g. [1], [3-5].\n\n" +
    "Structure:\n" +
    "# Key Topics\n<...>\n" +
    "# User Requests & Goals\n<...>\n" +
    "# Decisions & Changes Made\n<...>\n" +
    "# Current Status\n<...>"
  );

  var userPrompt = "";
  if (previousSummary && previousSummary.trim().length > 0) {
    userPrompt += "## Previous Compacted Summary:\n" + previousSummary.trim() + "\n\n";
  }
  userPrompt += "## Conversation Transcript to Compact:\n" + transcript + "\n\n";
  userPrompt += "Produce the updated compact summary with message ID citations:";

  var messages = [
    { role: "system", content: instructions },
    { role: "user", content: userPrompt }
  ];

  var streamOpts = {
    endpoint: providerOptions.endpoint,
    apiKey: providerOptions.apiKey || "",
    model: providerOptions.model,
    stream: true,
    temperature: 0.2,
    maxTokens: 2048
  };

  var accumulated = "";
  try {
    Api.streamChatCompletion(providerId, streamOpts, messages, {
      onToken: function(tok) {
        accumulated += tok;
      },
      onThinking: function() {},
      onDone: function(finalText) {
        if (callback) callback(null, (finalText || accumulated).trim());
      },
      onError: function(err) {
        if (callback) callback(err, null);
      }
    });
  } catch (e) {
    if (callback) callback("Failed to invoke compaction: " + (e.message || e), null);
  }
}
