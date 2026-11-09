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
    let sending = false;
    let historyMutationInProgress = false;
    let sessionLockPending = true;
    let heartbeatCount = 0;
    let currentStatusMessage = '';
    let currentStatusError = false;
    let currentRawOutputLabel = '';

    function updateSendDisabled() {
        send.disabled = sending || historyMutationInProgress || sessionLockPending;
    }

    window.addEventListener('maia:history-mutation', (event) => {
        historyMutationInProgress = event.detail?.busy === true;
        updateSendDisabled();
    });
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
        rawOutputFollowPaused.set(pre, false);
        rawOutputLastScrollTops.set(pre, pre.scrollTop);
        pre.addEventListener('scroll', () => {
            const currentScrollTop = pre.scrollTop;
            const previousScrollTop = rawOutputLastScrollTops.get(pre) ?? currentScrollTop;
            const nearBottom = rawOutputIsNearBottom(pre);
            if (currentScrollTop < previousScrollTop || !nearBottom) {
                rawOutputFollowPaused.set(pre, true);
                noteRawOutputInteraction(pre);
            } else if (currentScrollTop > previousScrollTop && nearBottom) {
                rawOutputFollowPaused.set(pre, false);
            }
            rawOutputLastScrollTops.set(pre, currentScrollTop);
        }, { passive: true });
        section.append(heading, pre, waiting);
        liveOutput = { section, waiting, label, pre, received: false };
        return section;
    }

    function selectedWithin(node) {
        const selection = document.getSelection();
        return Boolean(node && selection && !selection.isCollapsed &&
            (node.contains(selection.anchorNode) || node.contains(selection.focusNode)));
    }

    let rawOutputPointerSelecting = false;
    const rawOutputScrollVersions = new WeakMap();
    const rawOutputFollowPaused = new WeakMap();
    const rawOutputLastScrollTops = new WeakMap();
    function rawOutputIsNearBottom(pre) {
        return pre.scrollHeight - pre.clientHeight - pre.scrollTop <= 32;
    }
    function rawOutputScrollVersion(pre) {
        return rawOutputScrollVersions.get(pre) || 0;
    }
    function noteRawOutputInteraction(pre) {
        rawOutputScrollVersions.set(pre, rawOutputScrollVersion(pre) + 1);
    }
    function rawOutputFromEvent(event) {
        return event.target instanceof Element
            ? event.target.closest('.session-history-raw-output-content')
            : null;
    }
    document.addEventListener('pointerdown', (event) => {
        const pre = rawOutputFromEvent(event);
        if (!pre) return;
        noteRawOutputInteraction(pre);
        if (event.isPrimary && event.button === 0) rawOutputPointerSelecting = true;
    });
    document.addEventListener('wheel', (event) => {
        const pre = rawOutputFromEvent(event);
        if (!pre) return;
        noteRawOutputInteraction(pre);
        if (event.deltaY < 0) {
            // Preserve the reader's intent even if the panel cannot move yet.
            rawOutputFollowPaused.set(pre, true);
        } else if (event.deltaY > 0 && rawOutputIsNearBottom(pre)) {
            rawOutputFollowPaused.set(pre, false);
        }
    }, { passive: true });
    const endRawOutputPointerSelection = () => {
        // Let the browser establish the final Selection before allowing follow-scroll again.
        window.setTimeout(() => { rawOutputPointerSelecting = false; }, 0);
    };
    window.addEventListener('pointerup', endRawOutputPointerSelection);
    window.addEventListener('pointercancel', endRawOutputPointerSelection);

    function hasRawOutputSelection() {
        const selection = document.getSelection();
        if (!selection || selection.isCollapsed) return false;
        return Array.from(document.querySelectorAll('.session-history-raw-output-content')).some((pre) =>
            pre.contains(selection.anchorNode) || pre.contains(selection.focusNode));
    }

    function shouldFollowRawOutput(pre) {
        // Follow only if the reader was already at the bottom. Scrolling up to
        // inspect earlier output hands scroll control back to the user.
        if (rawOutputPointerSelecting || hasRawOutputSelection() || rawOutputFollowPaused.get(pre) === true) return false;
        return rawOutputIsNearBottom(pre);
    }

    const rawOutputScrollFrames = new WeakMap();
    function followRawOutput(pre, interactionVersion = rawOutputScrollVersion(pre)) {
        const previousFrame = rawOutputScrollFrames.get(pre);
        if (previousFrame !== undefined) window.cancelAnimationFrame(previousFrame);
        const frame = window.requestAnimationFrame(() => {
            rawOutputScrollFrames.delete(pre);
            // Recheck at paint time: the user may have started selecting or
            // manually scrolling since the chunk arrived.
            if (!pre.isConnected || rawOutputPointerSelecting || hasRawOutputSelection() ||
                rawOutputFollowPaused.get(pre) === true ||
                rawOutputScrollVersion(pre) !== interactionVersion) return;
            pre.scrollTop = pre.scrollHeight;
        });
        rawOutputScrollFrames.set(pre, frame);
    }

    function preserveViewport(operation) {
        if (window.maiaSessionViewport?.preserve) return window.maiaSessionViewport.preserve(operation);
        return operation();
    }

    const pendingFinalOutputs = new Set();
    function flushPendingFinalOutputs() {
        for (const pending of pendingFinalOutputs) {
            if (selectedWithin(pending.pre)) continue;
            pendingFinalOutputs.delete(pending);
            preserveViewport(() => renderFinalOutput(pending.pre, pending.output));
        }
    }
    document.addEventListener('selectionchange', flushPendingFinalOutputs);

    function appendRawOutputChunk(chunk) {
        if (!liveOutput) beginRawOutput();
        if (!chunk) return;
        const pre = liveOutput.pre;
        const follow = shouldFollowRawOutput(pre);
        const interactionVersion = rawOutputScrollVersion(pre);
        preserveViewport(() => {
            if (!liveOutput.received) {
                liveOutput.received = true;
                setRawOutputLabel('Receiving data...');
            }
            pre.appendChild(document.createTextNode(chunk));
            if (follow) followRawOutput(pre, interactionVersion);
        });
    }

    function renderFinalOutput(pre, output) {
        const follow = shouldFollowRawOutput(pre);
        const interactionVersion = rawOutputScrollVersion(pre);
        pre.replaceChildren();
        if (output === '') {
            pre.textContent = '(No output received.)';
            if (follow) followRawOutput(pre, interactionVersion);
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
        if (follow) followRawOutput(pre, interactionVersion);
    }

    function finishRawOutput(output) {
        if (!liveOutput) beginRawOutput();
        if (selectedWithin(liveOutput.pre)) {
            pendingFinalOutputs.add({ pre: liveOutput.pre, output });
        } else {
            preserveViewport(() => renderFinalOutput(liveOutput.pre, output));
        }
        liveOutput.waiting.hidden = true;
        liveOutput.section.classList.remove('session-history-live-output');
        liveOutput = null;
    }

    function withHeartbeatDots(message) {
        return heartbeatCount > 0 && message ? `${message} ${'.'.repeat(heartbeatCount)}` : message;
    }

    function setStatus(message, error = false) {
        currentStatusMessage = message;
        currentStatusError = error;
        const displayedMessage = withHeartbeatDots(message);
        if (error) window.maiaUi.setStatus(status, displayedMessage, { error: true });
        else if (message) window.maiaUi.setLoadingStatus(status, displayedMessage);
        else window.maiaUi.setStatus(status, '');
    }

    function setRawOutputLabel(message) {
        currentRawOutputLabel = message;
        if (liveOutput) liveOutput.label.textContent = withHeartbeatDots(message);
    }

    function resetHeartbeatDots() {
        heartbeatCount = 0;
        if (currentStatusMessage) setStatus(currentStatusMessage, currentStatusError);
        if (currentRawOutputLabel) setRawOutputLabel(currentRawOutputLabel);
    }

    async function waitForSessionUnlock() {
        if (!session) {
            sessionLockPending = false;
            updateSendDisabled();
            return;
        }
        sessionLockPending = true;
        updateSendDisabled();
        setStatus('Checking session lock...');
        while (true) {
            try {
                const lockStatus = await window.maiaApi.request('/api/session/lock-status');
                if (!lockStatus.locked) {
                    sessionLockPending = false;
                    updateSendDisabled();
                    if (!sending) setStatus('');
                    return;
                }
                setStatus('Waiting for the active send to finish...');
            } catch (_) {
                setStatus('Unable to check session lock; retrying...');
            }
            await new Promise((resolve) => window.setTimeout(resolve, 10000));
        }
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

    async function reconcileInterruptedSend(requestWasAccepted = false) {
        let checkedUnlockedOnce = false;
        while (true) {
            let lockStatus;
            try {
                lockStatus = await window.maiaApi.request('/api/session/lock-status');
            } catch (_) {
                setStatus('Unable to check send status; retrying...');
                await new Promise((resolve) => window.setTimeout(resolve, 10000));
                continue;
            }

            if (lockStatus.locked) {
                setStatus('The send is still running...');
                await new Promise((resolve) => window.setTimeout(resolve, 10000));
                continue;
            }

            // The send endpoint acknowledges receipt just before its CLI process
            // acquires the session lock. Recheck once after startup to avoid
            // treating that brief gap as a completed send.
            if (requestWasAccepted && !checkedUnlockedOnce) {
                checkedUnlockedOnce = true;
                await new Promise((resolve) => window.setTimeout(resolve, 2000));
                continue;
            }
            break;
        }

        const refreshed = await refreshHistory();
        if (!refreshed?.ok || !refreshed.completed) dispatch('maia:send-failure-settled');
        return refreshed;
    }

    waitForSessionUnlock();

    form.addEventListener('submit', async (event) => {
        event.preventDefault();
        const message = input.value;
        if (!message.trim() || !session || send.disabled) return;

        sending = true;
        heartbeatCount = 0;
        currentRawOutputLabel = 'Waiting for response...';
        input.disabled = true;
        updateSendDisabled();
        setStatus('Sending message...');
        const rawOutputNode = beginRawOutput();
        dispatch('maia:send-start', { message, outputNode: rawOutputNode });
        let output = '';
        let pendingProtocolLine = '';
        let protocolLinesRead = 0;
        let protocolError = '';
        const expectedProtocolLines = ['MAIA-REQUEST-START', 'MAIA-REQUEST-RECEIVED'];
        const heartbeatToken = `${String.fromCharCode(30)}MAIA-HEARTBEAT${String.fromCharCode(31)}`;
        let heartbeatSuffix = '';
        const stripHeartbeatTokens = (text, final = false) => {
            let remaining = heartbeatSuffix + text;
            heartbeatSuffix = '';
            let visible = '';
            let tokenIndex;
            while ((tokenIndex = remaining.indexOf(heartbeatToken)) !== -1) {
                visible += remaining.slice(0, tokenIndex);
                remaining = remaining.slice(tokenIndex + heartbeatToken.length);
                heartbeatCount += 1;
                if (currentStatusMessage) setStatus(currentStatusMessage, currentStatusError);
                if (currentRawOutputLabel) setRawOutputLabel(currentRawOutputLabel);
            }
            if (final) return visible + remaining;
            let suffixLength = 0;
            const maxSuffixLength = Math.min(remaining.length, heartbeatToken.length - 1);
            for (let length = maxSuffixLength; length > 0; length -= 1) {
                if (heartbeatToken.startsWith(remaining.slice(-length))) {
                    suffixLength = length;
                    break;
                }
            }
            if (suffixLength > 0) {
                heartbeatSuffix = remaining.slice(-suffixLength);
                remaining = remaining.slice(0, -suffixLength);
            }
            return visible + remaining;
        };
        const appendVisibleOutput = (text) => {
            if (text === '') return;
            if (!liveOutput || !liveOutput.received) setStatus('Receiving data...');
            output += text;
            appendRawOutputChunk(text);
            dispatch('maia:send-chunk', { chunk: text });
        };
        const appendOutput = (text) => appendVisibleOutput(stripHeartbeatTokens(text));
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
            appendVisibleOutput(stripHeartbeatTokens('', true));
            resetHeartbeatDots();

            const leading = output.trimStart();
            const explicitError = leading.startsWith('[ERROR]')
                ? leading.split(/\r?\n/, 1)[0]
                : '';
            if (protocolError || explicitError || !response.ok) {
                const messageText = 'Send error';
                finishRawOutput(output);
                dispatch('maia:send-failure', { output, error: messageText });
                await refreshHistory();
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
            resetHeartbeatDots();
            const messageText = 'Send error';
            finishRawOutput(output);
            dispatch('maia:send-failure', { output, error: messageText });
            const refreshed = await reconcileInterruptedSend(protocolLinesRead >= expectedProtocolLines.length);
            if (refreshed?.ok && refreshed.completed) {
                input.value = '';
                setStatus('Response completed; raw output may be incomplete.');
            } else {
                setStatus(messageText, true);
            }
        } finally {
            sending = false;
            input.disabled = false;
            updateSendDisabled();
            // Refocusing the composer can clear a document text selection and
            // trigger a deferred history render that moves the viewport.
            const selection = document.getSelection();
            if (!selection || selection.isCollapsed) input.focus({ preventScroll: true });
        }
    });
})();
