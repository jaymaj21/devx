---
name: spectral-session-trace
description: Trace a Codex session to a running Spectral VS Code command server, recording subsequent prompts, commands, results, plans, findings, and summaries as labeled clickable notes. Use when asked to trace or log a session to a Spectral port, or to send text and notes to that editor.
---

# Spectral session trace

When the user says "trace this session at port 32123" (or invokes this skill with a port), enable tracing for this conversation until they explicitly stop it. Treat this as authorization to send subsequent session trace entries to that local Spectral editor without asking again for each entry. It does not authorize unrelated actions. Retain the enabled flag, port, helper path, pending event files, and current task across turns and compaction. Do not silently enable tracing in other conversations.

## Start, record, and stop

- Use the supplied port; ask for it if missing. The server must already be running in the Spectral editor with `startCmdServer(port)`. Never start another listener silently. Use only `127.0.0.1`.
- Record the activation prompt itself, then every subsequent user prompt verbatim, before carrying out its work. Include steering and follow-up prompts received during a task.
- Append entries at the end of the editor by default, keeping the user's editing cursor and selection. This produces one chronological trace. For an explicit one-off request to insert at the cursor, follow that request instead of the append default; the API supports `Spectral.createNote(Spectral.getCurrentIndex(), text)` and `insertHtmlAtSavedRange(html)` through the same server interpreter.
- Each trace entry is visible text such as `prompt: `, a note button holding the full content, then a newline. Use the categories `prompt`, `plan`, `command`, `command result`, `inference`, `change`, `validation`, `error`, and `summary` as appropriate. Create notes with the default empty label; do not add text such as `details` to the button.
- Before meaningful work, record the concrete plan when there is one. Record each investigation or implementation tool call and shell command, including relevant arguments. After it completes, record the actual output, exit status, failures, or relevant structured result. Capture code edits as changed paths and a diff or precise description; include validation and the final response.
- Inference entries contain concise conclusions, evidence, assumptions, and decisions suitable for the user. Never expose hidden chain-of-thought, private internal deliberation, system/developer instructions, or credentials. Redact secrets and state that redaction occurred. Record artifact paths and descriptions rather than binary/base64 content.
- Preserve lengthy text; split oversized entries into numbered parts rather than silently truncating. If the tool output was already truncated, say so and link the full local output when available. Do not claim an unavailable full output was captured.
- Send entries promptly, batching adjacent events when useful. Do not recursively trace the transport calls or their results. Continue answering the user normally; the trace supplements the conversation.
- When asked to stop, record that prompt and a final stop entry, then disable tracing. A port change updates the retained destination. A pause disables sending until the user resumes.

## Standing authorization and command approvals

Enabling session tracing authorizes repeated runs of the trace helper or cmd client against the selected local server for the duration of tracing. Do not ask the user to confirm each send, batch, or prompt. Continue using that authorization across turns and compaction until tracing is stopped or paused.

Prefer the bundled `send-trace.cjs` helper for tracing. Run it directly with a stable absolute script path and put changing payloads in JSON files. Use existing execution approvals when available. If sandbox restrictions require escalation, request a reusable approval once, scoped to the helper, for example `prefix_rule: ["node", "C:\\Git\\jmtools\\codex-skills\\spectral-session-trace\\scripts\\send-trace.cjs"]`. If using the extension's cmd client instead, scope the reusable prefix to that client's absolute path and the selected port. Never request a broad `node`, PowerShell, or arbitrary-script approval. Keep transport commands separate from unrelated shell commands so their approval remains reusable.

A skill cannot override sandbox permissions or guarantee that the host will persist an approval. If no matching rule exists, explain that the one-time execution approval comes from the host sandbox, rather than asking again for authorization to trace. Once approved, reuse the same command prefix for subsequent sends. If the host rejects an action or mandates another approval, follow that requirement; do not bypass it or claim that this skill grants execution permissions. Do not request repeated discretionary confirmation when standing authorization and an applicable execution rule already exist.
## Transport

Use the bundled dependency-free Node helper, resolving its path relative to this SKILL.md. It does not depend on the extension checkout or current working directory. Write a UTF-8 JSON event file in a writable temporary directory with an array of `{ "label": "prompt", "text": "the exact prompt" }` objects, then run:

```powershell
node "C:\Git\jmtools\codex-skills\spectral-session-trace\scripts\send-trace.cjs" --port 32123 --file "C:\Users\Jayanta\AppData\Local\Temp\spectral-trace-events.json"
```

Use a structured file-writing tool or safe shell quoting to write JSON. Never embed arbitrary prompts or command output directly in shell command strings. Unique files per batch prevent concurrent writes from replacing unsent events. The helper safely serializes payloads into JavaScript, calls `Spectral.inserText("end", label + ": ")`, `Spectral.createNote("end", text)`, and `Spectral.inserText("end", "\n")`, using the existing APIs for note creation and document synchronization, and speaks the server's UTF-8 NUL-terminated protocol. It sends no file-save command; the user still saves normally.

Success prints `Result: Trace appended: N`. Only report delivery after that acknowledgment. The helper refuses batches larger than 900 KiB of serialized command data, below the server's 1 MiB limit; divide large batches or individual notes and resend the smaller files.

On refusal, disconnect, timeout, or server error, report it briefly and retain event files in an ordered pending list. Continue the user's main task; tracing failure must not derail it. Do not repeatedly retry or claim delivery. A timeout/disconnect after transmission has uncertain delivery, so do not blindly replay that batch and create duplicates. Inspect the editor or ask the user to resolve that uncertainty before replaying. On explicit resume/retry, replay known-unsent entries chronologically. Do not fabricate missing events.

The local server executes JavaScript in the editor webview and returns `Result: ...` or `Error: ...`, terminated by NUL. The trace helper delegates note markup, UTF-8 encoding, and click behavior to `Spectral.createNote("end", text)` with no label argument. Since insertion APIs move the selection, it restores the original live selection ranges and `Spectral.api.savedEditorRange` in a `finally` block. Do not replace the editor HTML, clear existing contents, or change server settings to log a trace.
