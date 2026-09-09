.pragma library

// System Telemetry & Prompt Interpolator for Omarchy LLM

function formatMarkdown(info) {
  if (!info || typeof info !== "object") return "- System information unavailable";

  var lines = [];
  if (info.timestamp) lines.push("- **Date & Time**: " + info.timestamp);
  if (info.os) lines.push("- **OS**: " + info.os + " (" + (info.arch || "x86_64") + ")");
  if (info.kernel) lines.push("- **Kernel**: " + info.kernel);
  if (info.desktop) lines.push("- **Desktop Compositor**: " + info.desktop);
  if (info.theme) lines.push("- **Omarchy Theme**: " + info.theme);
  if (info.cpu) lines.push("- **CPU**: " + info.cpu);
  if (info.memory) lines.push("- **RAM**: " + info.memory);
  if (info.user) lines.push("- **User**: `" + info.user + "` (Shell: `" + (info.shell || "bash") + "`)");
  if (info.activeWindow && info.activeWindow !== "None (Desktop)") {
    lines.push("- **Focused App**: " + info.activeWindow + " (Workspace " + (info.workspace || "1") + ")");
  }
  return lines.join("\n");
}

function interpolatePrompt(template, info, memories) {
  var tpl = template || "";
  var sysMarkdown = formatMarkdown(info);

  var prompt = tpl.replace("{{system_info}}", sysMarkdown);

  if (memories && memories.length > 0) {
    prompt = prompt.replace("{{memories}}", "## User Memories\n" + memories);
  } else {
    prompt = prompt.replace("{{memories}}", "");
  }

  return prompt.trim();
}
