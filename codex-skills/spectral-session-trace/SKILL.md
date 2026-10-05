---
name: spectral-session-trace
description: Trace a Codex session to a running Spectral JavaScript/VS Code or Tcl/Tk command server, recording subsequent prompts, commands, results, plans, findings, and summaries as labeled clickable notes. Use when asked to trace or log a session to a Spectral port, or to send text and notes to that editor.
---

# Spectral session trace

When the user asks to activate tracing with a recorder type (`js` or `tcl`) and port, enable tracing for this conversation until they explicitly stop it. Treat this as authorization to send subsequent session trace entries to that local Spectral editor without asking again for each entry. It does not authorize unrelated actions. Retain the enabled flag, recorder type, port, helper path, pending event files with their recorder/port destination, and current task across turns and compaction. Do not silently enable tracing in other conversations.

## Start, record, and stop

- Use the supplied recorder type (`js` or `tcl`) and port. Ask for either if missing on a new activation; an explicit resume can reuse the retained destination. Do not infer the language from the port or switch an active recorder without an instruction. The server must already be running: JavaScript `startCmdServer(port)` or Tcl Quick Command `startCmdServer port`. Never start another listener silently. Use only `127.0.0.1`.
- Record the activation prompt itself, then every subsequent user prompt verbatim, before carrying out its work. Include steering and follow-up prompts received during a task.
- Append entries at the end of the editor by default, keeping the user's editing cursor and selection. This produces one chronological trace. For an explicit one-off request to insert at the cursor, follow that request instead of the append default; JavaScript supports `Spectral.createNote(Spectral.getCurrentIndex(), text)` and `insertHtmlAtSavedRange(html)`; Tcl supports `create_note insert text` and `insert_text insert text` using safely serialized arguments. The bundled helper appends only; use the matching API directly for an explicit cursor insertion.
- Each trace entry is visible text such as `prompt: `, a note button holding the full content, then a newline. Use the categories `prompt`, `plan`, `command`, `command result`, `inference`, `change`, `validation`, `error`, and `summary` as appropriate. Use the recorder's default note button: JavaScript `Spectral.createNote("end", text)` with no label argument; Tcl `create_note end text` has no label argument and displays `N`. Do not add labels such as `details`.
- Before meaningful work, record the concrete plan when there is one. Record each investigation or implementation tool call and shell command, including relevant arguments. After it completes, record the actual output, exit status, failures, or relevant structured result. Capture code edits as changed paths and a diff or precise description; include validation and the final response.
- Inference entries contain concise conclusions, evidence, assumptions, and decisions suitable for the user. Never expose hidden chain-of-thought, private internal deliberation, system/developer instructions, or credentials. Redact secrets and state that redaction occurred. Record artifact paths and descriptions rather than binary/base64 content.
- Preserve lengthy text; split oversized entries into numbered parts rather than silently truncating. If the tool output was already truncated, say so and link the full local output when available. Do not claim an unavailable full output was captured.
- Record every user-visible assistant commentary message verbatim as a plan, inference, or other appropriate category. Record the complete final response verbatim as a summary before delivering that same response to the user; do not substitute a shortened summary. Include lists, caveats, paths, links, examples, and code blocks. Split oversized messages into numbered parts without omitting content. When a user identifies an omitted message, backfill the known message verbatim and mark it as a backfill.
- User-visible explanations of findings, evidence, assumptions, and decisions can be recorded in full. Private internal chain-of-thought is excluded; provide a concise public reasoning summary when useful.
- Send entries promptly, batching adjacent events when useful. Do not recursively trace the transport calls or their results. Continue answering the user normally; the trace supplements the conversation.
- When asked to stop, record that prompt and a final stop entry, then disable tracing. A recorder type or port change updates the retained destination; keep pending entries attached to their original destination unless the user asks to redirect them. A pause disables sending until the user resumes.

## Standing authorization and command approvals

Enabling session tracing authorizes repeated runs of the trace helper or cmd client against the selected local server for the duration of tracing. Do not ask the user to confirm each send, batch, or prompt. Continue using that authorization across turns and compaction until tracing is stopped or paused.

Prefer the bundled `send-trace.cjs` helper for tracing. Run it directly with a stable absolute script path and put changing payloads in JSON files. Use existing execution approvals when available. If sandbox restrictions require escalation, request a reusable approval once, scoped to the helper, for example `prefix_rule: ["node", "C:\\Git\\jmtools\\codex-skills\\spectral-session-trace\\scripts\\send-trace.cjs"]`. If using the extension's cmd client instead, scope the reusable prefix to that client's absolute path and the selected port. Never request a broad `node`, PowerShell, or arbitrary-script approval. Keep transport commands separate from unrelated shell commands so their approval remains reusable.

A skill cannot override sandbox permissions or guarantee that the host will persist an approval. If no matching rule exists, explain that the one-time execution approval comes from the host sandbox, rather than asking again for authorization to trace. Once approved, reuse the same command prefix for subsequent sends. If the host rejects an action or mandates another approval, follow that requirement; do not bypass it or claim that this skill grants execution permissions. Do not request repeated discretionary confirmation when standing authorization and an applicable execution rule already exist.
## Transport

Use the bundled dependency-free Node helper, resolving its path relative to this SKILL.md. It does not depend on the extension checkout or current working directory. Write a UTF-8 JSON event file in a writable temporary directory with an array of `{ "label": "prompt", "text": "the exact prompt" }` objects, then run:

```powershell
node "scripts/send-trace.cjs" --recorder js --port 32123 --file "C:\Users\Jayanta\AppData\Local\Temp\spectral-trace-events.json"
```

For a Tcl recorder, use the same helper with `--recorder tcl` and the supplied Tcl server port. Activation examples: "activate spectral-session-trace with a js recorder on port 32123" or "activate spectral-session-trace with a tcl recorder on port 32124". Always pass `--recorder` explicitly; the helper retains its legacy JS default only for backwards compatibility.

Use a structured file-writing tool or safe shell quoting to write JSON. Never embed arbitrary prompts or command output directly in shell command strings. Unique files per batch prevent concurrent writes from replacing unsent events. For `js`, the helper safely serializes payloads into JavaScript and calls `Spectral.inserText("end", label + ": ")`, `Spectral.createNote("end", text)`, and `Spectral.inserText("end", "\n")`, using the existing APIs for note creation and document synchronization. For `tcl`, it calls `insert_text end "label: "`, `create_note end text`, and `insert_text end "\n"`, preserving the insertion mark, selection and viewport in `try/finally`. It encodes each string as UTF-8 base64 and uses `[encoding convertfrom utf-8 [binary decode base64 {...}]]`, so arbitrary trace text is data, never Tcl code. Both modes use the same UTF-8 NUL-terminated TCP protocol. It sends no file-save command; the user still saves normally.

Success prints `Result: Trace appended: N`. Only report delivery after that acknowledgment. The helper refuses batches larger than 900 KiB of serialized command data, below the server's 1 MiB limit; divide large batches or individual notes and resend the smaller files.

On refusal, disconnect, timeout, or server error, report it briefly and retain event files in an ordered pending list. Continue the user's main task; tracing failure must not derail it. Do not repeatedly retry or claim delivery. A timeout/disconnect after transmission has uncertain delivery, so do not blindly replay that batch and create duplicates. Inspect the editor or ask the user to resolve that uncertainty before replaying. On explicit resume/retry, replay known-unsent entries chronologically. Do not fabricate missing events.

The JS server executes JavaScript in the editor webview; the Tcl server executes Tcl in the main editor interpreter. Both return `Result: ...` or `Error: ...`, terminated by NUL. In JS mode, the trace helper delegates note markup, UTF-8 encoding, and click behavior to `Spectral.createNote("end", text)` with no label argument. Since insertion APIs move the selection, it restores the original live selection ranges and `Spectral.api.savedEditorRange` in a `finally` block. Do not replace the editor HTML, clear existing contents, or change server settings to log a trace.

## Tcl recorder API

- `insert_text pos txt {tag ""}` accepts a Tk text index (`end`, `insert`, `line.character`). Omit the optional tag for trace labels and newlines; it inserts through `.t` without forcing a save.
- `create_note pos txt` writes the note body as UTF-8 into the current document's Spectral subfolder, embeds an `N` button, and sets the editor modified flag. It returns an empty string on success; do not treat a falsy return as failure. These note files are an inherent part of Tcl recording and are authorized by activating it.
- `.t` is the Tcl editor widget. The helper appends before its mandatory final newline and adds a separator newline when existing content needs one. Tcl notes differ from the JS recorder's embedded HTML note data; preserve each recorder's normal format.

## Helper validation

Run `node scripts/test-send-trace.cjs <path/to/spectral_on_barebones.tk>` to check recorder argument validation, size limits, JS behavior, and Tcl behavior using the actual insertion procedures in an isolated hidden Tk widget. Requires Tcl/Tk on PATH (`TCLSH` can select an executable). The test creates and removes temporary note files; it does not connect to the user's recorder.
