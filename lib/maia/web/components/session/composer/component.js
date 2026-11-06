/* Streaming message composer for a session page. */
(() => {
    'use strict';
    const form = document.querySelector('[data-session-composer]');
    if (!form) return;
    const input = form.querySelector('textarea');
    const send = form.querySelector('[data-composer-send]');
    const status = form.querySelector('[data-composer-status]');
    const sessionLabel = form.querySelector('[data-composer-session]');
    const session = String(document.body.dataset.maiaSession || '');
    let liveOutput = null;
    if (sessionLabel) sessionLabel.textContent = session;

    function beginRawOutput() {
        const section = document.createElement('details');
        section.className = 'session-history-raw-output-item session-history-live-output';
        section.open = true;
        const heading = document.createElement('summary');
        heading.textContent = 'Raw output';
        const waiting = document.createElement('div');
        waiting.className = 'session-history-live-output-waiting';
        const spinner = document.createElement('span');
        spinner.className = 'spinner';
        spinner.setAttribute('aria-hidden', 'true');
        const label = document.createElement('span');
        label.textContent = 'Waiting for response...';
        waiting.append(spinner, label);
        const pre = document.createElement('pre');
        pre.className = 'session-history-raw-output-content';
        section.append(heading, waiting, pre);
        liveOutput = { section, waiting, label, pre, received: false };
        return section;
    }

    function appendRawOutputChunk(chunk) {
        if (!liveOutput) beginRawOutput();
        if (!chunk) return;
        if (!liveOutput.received) {
            liveOutput.received = true;
            liveOutput.label.textContent = 'Receiving data...';
        }
        liveOutput.pre.appendChild(document.createTextNode(chunk));
    }

    function renderFinalOutput(pre, output) {
        pre.replaceChildren();
        if (output === '') {
            pre.textContent = '(No output received.)';
            return;
        }
        const pattern = /\[ERROR\]/g;
        const firstVisibleCharacter = output.search(/\S/);
        let offset = 0;
        let match;
        while ((match = pattern.exec(output)) !== null) {
            if (match.index > offset) pre.appendChild(document.createTextNode(output.slice(offset, match.index)));
            const marker = document.createElement('span');
            marker.className = match.index === firstVisibleCharacter
                ? 'session-composer-output-error-leading'
                : 'session-composer-output-error-later';
            marker.textContent = match[0];
            pre.appendChild(marker);
            offset = match.index + match[0].length;
        }
        if (offset < output.length) pre.appendChild(document.createTextNode(output.slice(offset)));
    }

    function finishRawOutput(output) {
        if (!liveOutput) beginRawOutput();
        renderFinalOutput(liveOutput.pre, output);
        liveOutput.waiting.hidden = true;
        liveOutput.section.classList.remove('session-history-live-output');
        liveOutput = null;
    }

    function setStatus(message, error = false) {
        if (error) window.maiaUi.setStatus(status, message, { error: true });
        else if (message) window.maiaUi.setLoadingStatus(status, message);
        else window.maiaUi.setStatus(status, '');
    }

    function setRawOutputLabel(message) {
        if (liveOutput && !liveOutput.received) liveOutput.label.textContent = message;
    }

    function dispatch(name, detail = {}) {
        window.dispatchEvent(new CustomEvent(name, { detail }));
    }

    function refreshHistory() {
        return new Promise((resolve) => {
            let settled = false;
            const finish = (result) => {
                if (settled) return;
                settled = true;
                window.clearTimeout(timeout);
                resolve(result && typeof result === 'object'
                    ? result
                    : { ok: Boolean(result), error: '' });
            };
            const timeout = window.setTimeout(() => finish({
                ok: false,
                error: 'History refresh timed out after 60 seconds.'
            }), 60000);
            dispatch('maia:history-refresh', { done: finish });
        });
    }

    form.addEventListener('submit', async (event) => {
        event.preventDefault();
        const message = input.value;
        if (!message.trim() || !session || send.disabled) return;

        input.disabled = true;
        send.disabled = true;
        setStatus('Sending message...');
        const rawOutputNode = beginRawOutput();
        dispatch('maia:send-start', { message, outputNode: rawOutputNode });
        let output = '';
        let pendingProtocolLine = '';
        let protocolLinesRead = 0;
        let protocolError = '';
        const expectedProtocolLines = ['MAIA-REQUEST-START', 'MAIA-REQUEST-RECEIVED'];
        const appendOutput = (text) => {
            if (text === '') return;
            if (!liveOutput || !liveOutput.received) setStatus('Receiving data...');
            output += text;
            appendRawOutputChunk(text);
            dispatch('maia:send-chunk', { chunk: text });
        };
        const consumeResponseText = (text, final = false) => {
            pendingProtocolLine += text;
            const newlineCharacter = String.fromCharCode(10);

            while (protocolLinesRead < expectedProtocolLines.length) {
                const newline = pendingProtocolLine.indexOf(newlineCharacter);
                if (newline === -1) break;

                const line = pendingProtocolLine.slice(0, newline);
                const normalizedLine = line.endsWith(String.fromCharCode(13)) ? line.slice(0, -1) : line;
                if (normalizedLine !== expectedProtocolLines[protocolLinesRead]) {
                    protocolError = `Expected protocol line ${protocolLinesRead + 1} "${expectedProtocolLines[protocolLinesRead]}", received "${normalizedLine || '(empty line)'}".`;
                    appendOutput(pendingProtocolLine);
                    pendingProtocolLine = '';
                    protocolLinesRead = expectedProtocolLines.length;
                    return;
                }

                pendingProtocolLine = pendingProtocolLine.slice(newline + 1);
                protocolLinesRead += 1;
                if (protocolLinesRead === 1) {
                    setStatus('Message sent...');
                } else {
                    setStatus('Processing message...');
                }
            }

            if (final && protocolLinesRead < expectedProtocolLines.length) {
                protocolError = `Response ended before protocol line ${protocolLinesRead + 1} "${expectedProtocolLines[protocolLinesRead]}" was received.`;
                if (pendingProtocolLine !== '') appendOutput(pendingProtocolLine);
                pendingProtocolLine = '';
                return;
            }

            if (protocolLinesRead === expectedProtocolLines.length && pendingProtocolLine !== '') {
                appendOutput(pendingProtocolLine);
                pendingProtocolLine = '';
            } else if (final && pendingProtocolLine !== '') {
                appendOutput(pendingProtocolLine);
                pendingProtocolLine = '';
            }
        };
        try {
            const response = await fetch(window.maiaApi.url('/api/send'), {
                method: 'POST',
                headers: {
                    'Content-Type': 'text/plain; charset=utf-8',
                    'X-MAIA-Session': session
                },
                body: message
            });
            setStatus('Receiving response...');
            setRawOutputLabel('Receiving response...');
            if (response.body) {
                const reader = response.body.getReader();
                const decoder = new TextDecoder();
                while (true) {
                    const { value, done } = await reader.read();
                    if (done) break;
                    const chunk = decoder.decode(value, { stream: true });
                    if (chunk !== '') {
                        consumeResponseText(chunk);
                    }
                }
                const finalChunk = decoder.decode();
                consumeResponseText(finalChunk, true);
            } else {
                consumeResponseText(await response.text(), true);
            }

            const leading = output.trimStart();
            const explicitError = leading.startsWith('[ERROR]')
                ? leading.split(/\r?\n/, 1)[0]
                : '';
            if (protocolError || explicitError || !response.ok) {
                const messageText = 'Send error';
                finishRawOutput(output);
                dispatch('maia:send-failure', { output, error: messageText });
                setStatus(messageText, true);
                return;
            }

            finishRawOutput(output);
            dispatch('maia:send-complete', { output });
            setStatus('Updating conversation...');
            const refreshed = await refreshHistory();
            if (refreshed?.ok) {
                input.value = '';
                setStatus('');
            } else {
                const detail = refreshed?.error ? ` ${refreshed.error}` : '';
                setStatus(`The message was sent, but the conversation could not be refreshed.${detail} The raw output is preserved.`, true);
            }
        } catch (error) {
            console.error('Session send failed:', error);
            const messageText = 'Send error';
            finishRawOutput(output);
            dispatch('maia:send-failure', { output, error: messageText });
            setStatus(messageText, true);
        } finally {
            input.disabled = false;
            send.disabled = false;
            input.focus();
        }
    });
})();
