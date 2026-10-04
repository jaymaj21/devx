'use strict';

const fs = require('node:fs');
const net = require('node:net');

function buildCommand(events) {
    if (!Array.isArray(events) || !events.length) throw new Error('Expected a nonempty array of events.');
    for (const event of events) {
        if (!event || typeof event.label !== 'string' || !event.label.trim() || typeof event.text !== 'string') {
            throw new Error('Each event requires a nonempty label and string text.');
        }
    }
    const payload = JSON.stringify(events).replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
    const command = `(() => {
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

async function main(args) {
    if (args.length !== 4 || args[0] !== '--port' || args[2] !== '--file') {
        throw new Error('Usage: node send-trace.cjs --port <port> --file <UTF-8 JSON events file>');
    }
    const port = Number(args[1]);
    if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Port must be an integer from 1 to 65535.');
    const events = JSON.parse(fs.readFileSync(args[3], 'utf8').replace(/^\uFEFF/, ''));
    process.stdout.write(await sendCommand(port, buildCommand(events)) + '\n');
}

if (require.main === module) {
    main(process.argv.slice(2)).catch(error => {
        process.stderr.write('Error: ' + error.message + '\n');
        process.exitCode = 1;
    });
}

module.exports = { buildCommand, sendCommand };
