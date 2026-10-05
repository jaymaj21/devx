'use strict';

const fs = require('node:fs');
const net = require('node:net');

function tclString(text) {
    return '[encoding convertfrom utf-8 [binary decode base64 {' + Buffer.from(text, 'utf8').toString('base64') + '}]]';
}

function buildTclCommand(events) {
    const entries = events.map(event => [
        'insert_text end ' + tclString(event.label + ': '),
        'create_note end ' + tclString(event.text),
        'insert_text end ' + tclString('\n')
    ].join('\n')).join('\n');
    return `apply {{} {
        foreach command {insert_text create_note .t} {
            if {![llength [info commands $command]]} {error "Spectral Tcl API unavailable: $command"}
        }
        set savedInsert [.t index insert]
        set savedSelection [.t tag ranges sel]
        set savedY [.t yview]
        set savedX [.t xview]
        try {
            if {[.t compare end-1c > 1.0] && [.t get end-2c end-1c] ne "\\n"} {
                insert_text end "\\n"
            }
            ${entries}
        } finally {
            .t mark set insert $savedInsert
            .t tag remove sel 1.0 end
            foreach {first last} $savedSelection {.t tag add sel $first $last}
            .t yview moveto [lindex $savedY 0]
            .t xview moveto [lindex $savedX 0]
        }
        set acknowledgment {Trace appended: ${events.length}}
    }}`;
}

function buildCommand(events, recorder = 'js') {
    if (!Array.isArray(events) || !events.length) throw new Error('Expected a nonempty array of events.');
    for (const event of events) {
        if (!event || typeof event.label !== 'string' || !event.label.trim() || typeof event.text !== 'string') {
            throw new Error('Each event requires a nonempty label and string text.');
        }
    }
    if (!['js', 'tcl'].includes(recorder)) throw new Error('Recorder must be js or tcl.');
    const payload = JSON.stringify(events).replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
    const command = recorder === 'tcl' ? buildTclCommand(events) : `(() => {
        if (!window.Spectral || !Spectral.editor) throw new Error('Spectral API unavailable');
        const events = ${payload};
        const selection = window.getSelection();
        const ranges = [];
        for (let i = 0; i < selection.rangeCount; i++) ranges.push(selection.getRangeAt(i).cloneRange());
        const savedRange = Spectral.api.savedEditorRange;
        try {
            const text = Spectral.getPlainText();
            const newline = String.fromCharCode(10);
            if (text && !text.endsWith(newline)) Spectral.inserText('end', newline);
            for (const event of events) {
                Spectral.inserText('end', event.label + ': ');
                if (!Spectral.createNote('end', event.text)) throw new Error('Note creation failed');
                Spectral.inserText('end', newline);
            }
        } finally {
            selection.removeAllRanges();
            for (const range of ranges) selection.addRange(range);
            Spectral.api.savedEditorRange = savedRange;
        }
        return 'Trace appended: ' + events.length;
    })()`;
    if (Buffer.byteLength(command, 'utf8') > 900 * 1024) throw new Error('Batch exceeds 900 KiB; split entries into smaller batches.');
    return command;
}

function sendCommand(port, command, timeoutMs = 10000) {
    return new Promise((resolve, reject) => {
        const socket = net.createConnection({ host: '127.0.0.1', port });
        const chunks = [];
        let settled = false;
        const finish = (error, response) => {
            if (settled) return;
            settled = true;
            socket.destroy();
            error ? reject(error) : resolve(response);
        };
        socket.setTimeout(timeoutMs);
        socket.once('connect', () => socket.write(command + '\0', 'utf8'));
        socket.on('data', chunk => {
            chunks.push(chunk);
            const buffer = Buffer.concat(chunks);
            const end = buffer.indexOf(0);
            if (end < 0) return;
            const response = buffer.subarray(0, end).toString('utf8');
            if (!response.startsWith('Result: Trace appended: ')) finish(new Error(response));
            else finish(null, response);
        });
        socket.once('timeout', () => finish(new Error('Timed out; delivery may be uncertain. Do not automatically replay.')));
        socket.once('error', error => finish(error));
        socket.once('end', () => finish(new Error('Disconnected before acknowledgment; delivery may be uncertain.')));
    });
}

function parseArgs(args) {
    const options = { recorder: 'js' };
    const seen = new Set();
    for (let i = 0; i < args.length; i += 2) {
        const flag = args[i];
        if (!['--recorder', '--port', '--file'].includes(flag) || seen.has(flag) || !args[i + 1]) {
            throw new Error('Usage: node send-trace.cjs --recorder <js|tcl> --port <port> --file <UTF-8 JSON events file>');
        }
        seen.add(flag);
        options[flag.slice(2)] = args[i + 1];
    }
    if (!['js', 'tcl'].includes(options.recorder)) throw new Error('Recorder must be js or tcl.');
    const port = Number(options.port);
    if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Port must be an integer from 1 to 65535.');
    if (!options.file) throw new Error('An events file is required.');
    return { ...options, port };
}

async function main(args) {
    const options = parseArgs(args);
    const events = JSON.parse(fs.readFileSync(options.file, 'utf8').replace(/^\uFEFF/, ''));
    process.stdout.write(await sendCommand(options.port, buildCommand(events, options.recorder)) + '\n');
}

if (require.main === module) {
    main(process.argv.slice(2)).catch(error => {
        process.stderr.write('Error: ' + error.message + '\n');
        process.exitCode = 1;
    });
}

module.exports = { buildCommand, sendCommand, parseArgs };
