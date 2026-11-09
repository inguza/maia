/* Session history, display modes, entry actions and session operations. */
(() => {
    'use strict';
    const root = document.querySelector('.session-history');
    if (!root || !window.maiaApi || !window.maiaActionMenu) return;
    const role = (name) => root.querySelector(`[data-history-role="${name}"]`);
    const action = (name) => root.querySelector(`[data-history-action="${name}"]`);
    const status = role('status');
    const itemsNode = role('items');
    const composer = document.querySelector('[data-session-composer]');
    const earlierButton = action('earlier');
    const allButton = action('all');
    const turnCount = role('turn-count');
    const turnCountControl = role('turn-count-control');
    const remaining = role('remaining');
    const session = String(document.body.dataset.maiaSession || '');
    const basePath = String(window.MAIA_BASE_PATH || '').replace(/\/$/, '');
    const editDialog = root.querySelector('[data-history-dialog="edit"]');
    const settingsDialog = root.querySelector('[data-history-dialog="settings"]');
    const renameDialog = root.querySelector('[data-history-dialog="rename"]');
    const copyDialog = root.querySelector('[data-history-dialog="copy"]');
    let historyItems = [];
    let firstIndex = null;
    let lastIndex = null;
    let mode = 'collapsed';
    let loadingEarlier = false;
    let sessionSettings = null;
    let activeSend = null;
    let historyMutationCount = 0;
    let pendingRender = false;
    const sendEntries = [];

    async function withHistoryMutation(operation) {
        historyMutationCount++;
        window.dispatchEvent(new CustomEvent('maia:history-mutation', {
            detail: { busy: true }
        }));
        try {
            return await operation();
        } finally {
            historyMutationCount--;
            window.dispatchEvent(new CustomEvent('maia:history-mutation', {
                detail: { busy: historyMutationCount > 0 }
            }));
        }
    }

    function setStatus(message, isError = false, isLoading = false) {
        if (isLoading) window.maiaUi.setLoadingStatus(status, message);
        else window.maiaUi.setStatus(status, message, { error: isError });
    }
    function currentTextSelection() {
        const selection = document.getSelection();
        if (!selection || selection.isCollapsed || selection.rangeCount === 0) return null;
        return selection.getRangeAt(0);
    }
    function selectionIsInHistory() {
        const selection = document.getSelection();
        return Boolean(selection && !selection.isCollapsed &&
            (itemsNode.contains(selection.anchorNode) || itemsNode.contains(selection.focusNode)));
    }
    function viewportSnapshot(forceComposer = false) {
        const range = currentTextSelection();
        if (range) {
            const rect = range.getBoundingClientRect();
            if (rect.height > 0) return { type: 'selection', range: range.cloneRange(), top: rect.top };
        }
        if (!composer) return null;
        const textarea = composer.querySelector('textarea');
        const send = composer.querySelector('[data-composer-send]');
        if (!textarea || !send) return null;
        const textareaRect = textarea.getBoundingClientRect();
        const sendRect = send.getBoundingClientRect();
        const fullyVisible = (rect) => rect.top >= 0 && rect.bottom <= window.innerHeight;
        if (!forceComposer && (!fullyVisible(textareaRect) || !fullyVisible(sendRect))) return null;
        return { type: 'composer', textareaTop: textareaRect.top, sendTop: sendRect.top };
    }
    function scrollViewportBy(delta) {
        if (!Number.isFinite(delta) || Math.abs(delta) < 0.5) return;
        // Streaming can trigger this many times per second. Never let a global
        // scroll-behavior:smooth rule animate each correction into a jump.
        window.scrollBy({ top: delta, left: 0, behavior: 'instant' });
    }
    function preserveViewport(operation, forceComposer = false, preserveScrollPosition = false) {
        const snapshot = preserveScrollPosition
            ? { type: 'scroll-position', top: window.scrollY }
            : viewportSnapshot(forceComposer);
        let result;
        try {
            result = operation();
        } finally {
            if (snapshot?.type === 'selection' && snapshot.range.startContainer.isConnected && snapshot.range.endContainer.isConnected) {
                const rect = snapshot.range.getBoundingClientRect();
                if (rect.height > 0) scrollViewportBy(rect.top - snapshot.top);
            } else if (snapshot?.type === 'scroll-position') {
                scrollViewportBy(snapshot.top - window.scrollY);
            } else if (snapshot?.type === 'composer' && composer?.isConnected) {
                const textarea = composer.querySelector('textarea');
                const send = composer.querySelector('[data-composer-send]');
                if (textarea && send) {
                    const textareaDelta = textarea.getBoundingClientRect().top - snapshot.textareaTop;
                    const sendDelta = send.getBoundingClientRect().top - snapshot.sendTop;
                    scrollViewportBy((textareaDelta + sendDelta) / 2);
                }
            }
        }
        return result;
    }
    window.maiaSessionViewport = { preserve: (operation) => preserveViewport(operation) };
    document.addEventListener('selectionchange', () => {
        if (pendingRender && !selectionIsInHistory()) render(false, true);
    });
    function isHidden(item) { return item?.hidden === true || item?.hidden === 1 || item?.hidden === 'true'; }
    function formatTimestamp(value) {
        if (typeof value !== 'string') return '';
        const m = value.match(/^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})/);
        return m ? `${m[1]}-${m[2]}-${m[3]} ${m[4]}:${m[5]}:${m[6]}` : value;
    }
    function shortId(value) { return typeof value === 'string' && value.length > 16 ? `…${value.slice(-12)}` : (value || ''); }
    function parseArguments(value) {
        if (typeof value !== 'string') return JSON.stringify(value ?? {}, null, 2);
        try { return JSON.stringify(JSON.parse(value), null, 2); } catch (_) { return value; }
    }
    function appendText(parent, text, parts = null) {
        if (Array.isArray(parts) && parts.length) {
            for (const part of parts) {
                const value = String(part?.text ?? '');
                if (typeof part?.path === 'string' && part.path) {
                    const link = document.createElement('a');
                    const encoded = part.path.split('/').map(encodeURIComponent).join('/');
                    link.href = `${basePath}/session/${encodeURIComponent(part.session || session)}/${encoded}`;
                    link.textContent = value;
                    parent.appendChild(link);
                } else appendPlainText(parent, value);
            }
            return;
        }
        appendPlainText(parent, String(text ?? ''));
    }
    const urlPattern = /https?:\/\/[^\s<>"']+/gi;
    const changeReferencePattern = /\b(?:proposal\s+created|change\s+created\s+for\s+manual\s+resolution)\s*:\s*([A-Za-z0-9_.+-]+)/gi;
    function appendPlainText(parent, text) {
        const links = [];
        urlPattern.lastIndex = 0;
        for (const match of text.matchAll(urlPattern)) {
            let url = match[0];
            while (/[.,!?;:)\]}]$/.test(url)) url = url.slice(0, -1);
            const start = match.index ?? 0;
            if (url) links.push({ start, end: start + url.length, href: url, text: url, external: true });
        }
        changeReferencePattern.lastIndex = 0;
        for (const match of text.matchAll(changeReferencePattern)) {
            const rawId = match[1];
            const changeId = rawId.replace(/[.,;:!?)}\]]+$/, '');
            if (!changeId) continue;
            const start = (match.index ?? 0) + match[0].lastIndexOf(rawId);
            links.push({
                start,
                end: start + changeId.length,
                href: `${basePath}/changes/${encodeURIComponent(session)}/${encodeURIComponent(changeId)}`,
                text: changeId,
                title: `View change ${changeId}`
            });
        }
        links.sort((first, second) => first.start - second.start);
        let offset = 0;
        for (const candidate of links) {
            if (candidate.start < offset) continue;
            if (candidate.start > offset) parent.appendChild(document.createTextNode(text.slice(offset, candidate.start)));
            const link = document.createElement('a');
            link.href = candidate.href;
            link.textContent = candidate.text;
            if (candidate.external) {
                link.target = '_blank';
                link.rel = 'noopener noreferrer';
            } else if (candidate.title) {
                link.title = candidate.title;
            }
            parent.appendChild(link);
            offset = candidate.end;
        }
        if (offset < text.length) parent.appendChild(document.createTextNode(text.slice(offset)));
    }
    function appendMetadata(parent, item) {
        if (typeof item.timestamp !== 'string' || item.timestamp === '') return;
        const node = document.createElement('div'); node.className = 'session-history-metadata';
        const time = document.createElement('time');
        time.dateTime = item.timestamp;
        time.textContent = formatTimestamp(item.timestamp);
        time.title = item.timestamp;
        node.appendChild(time);
        parent.appendChild(node);
    }
    function selectEntry(element) {
        itemsNode.querySelectorAll('.session-history-entry-selected').forEach((node) => node.classList.remove('session-history-entry-selected'));
        element?.classList.add('session-history-entry-selected');
    }
    async function fetchHistory(range, signal) {
        const result = await window.maiaApi.request('/api/history/show', {
            method: 'POST', headers: { 'Content-Type': 'text/plain; charset=utf-8' }, body: range, signal
        });
        if (!Array.isArray(result.items)) throw new Error('MAIA returned invalid history items.');
        return result;
    }
    async function refreshHistoryAfterMutation() {
        const result = await fetchHistory('all');
        historyItems = result.items; firstIndex = result.firstIndex; lastIndex = result.lastIndex;
        render(); updateHistoryControls(); setStatus('');
    }
    async function performHistoryAction(actionName, item, content = null) {
        return withHistoryMutation(async () => {
            const body = { action: actionName, index: Number(item.index) };
            if (actionName === 'prune' || actionName === 'cut') {
                body.role = item.role; body.roleIndex = Number(item[`${item.role}_index`]);
            }
            if (actionName === 'replace') body.content = content ?? '';
            await window.maiaApi.request('/api/history/action', {
                method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body)
            });
            await refreshHistoryAfterMutation();
        });
    }
    function appendEntryActions(container, item) {
        if (!container || container.querySelector(':scope > .session-history-entry-actions')) return;
        const sourceItem = item.role === 'assistant'
            ? historyItems.find((candidate) => String(candidate.index) === String(item.index))
            : null;
        const hasToolCalls = item.role === 'assistant' && (
            (Array.isArray(item.tool_calls) && item.tool_calls.length > 0) ||
            (Array.isArray(sourceItem?.tool_calls) && sourceItem.tool_calls.length > 0)
        );
        container.classList.add('session-history-entry');
        const actions = document.createElement('div'); actions.className = 'session-history-entry-actions';
        const defs = [
            ['edit', '✎', 'Edit this entry'],
            [isHidden(item) ? 'unhide' : 'hide', isHidden(item) ? '⊙' : '⊘', isHidden(item) ? 'Unhide this entry' : 'Hide this entry'],
            ['prune', '≋', 'Reduce'], ['cut', '⌧', 'Clear this entry'],
            ['delete', '×', 'Delete this entry'], ['delete-below', '×↓', 'Delete this entry and all below']
        ];
        for (const [name, icon, label] of defs) {
            if (name === 'prune' && !['assistant', 'tool'].includes(item.role)) continue;
            const button = document.createElement('button'); button.type = 'button';
            button.className = 'session-history-entry-action'; button.textContent = icon;
            const description = hasToolCalls && ['hide', 'delete', 'delete-below'].includes(name)
                ? `${label} (also affects associated tool output)`
                : label;
            button.title = description; button.setAttribute('aria-label', description);
            const matchingCalls = item.role === 'tool'
                ? historyItems.filter((candidate) => candidate.role === 'assistant' && (candidate.tool_calls || []).some((call) => call?.id === item.tool_call_id))
                : [];
            if (item.role === 'tool' && matchingCalls.length && ['hide', 'delete', 'delete-below'].includes(name)) {
                button.disabled = true; button.title = 'Tool results cannot be hidden or deleted directly; act on the assistant tool call instead.'; button.setAttribute('aria-label', button.title);
            } else if (item.role === 'tool' && name === 'unhide' && (!matchingCalls.length || matchingCalls.every(isHidden))) {
                button.disabled = true; button.title = matchingCalls.length ? 'Unhide the assistant tool call first.' : 'This tool result has no matching assistant tool call.'; button.setAttribute('aria-label', button.title);
            }
            button.addEventListener('click', async (event) => {
                event.stopPropagation();
                if (name === 'edit') {
                    editDialog.dataset.index = String(item.index);
                    role('edit-content').value = String(item.content ?? '');
                    role('edit-error').hidden = true; editDialog.showModal(); role('edit-content').focus(); return;
                }
                const confirmText = name === 'delete-below' ? 'Delete this history entry and all entries below it? This cannot be undone.'
                    : name === 'delete' ? 'Delete this history entry? This cannot be undone.'
                    : name === 'cut' ? 'Clear/cut this history entry? Its original content will be retained as a backup.'
                    : name === 'prune' ? 'Reduce this history entry? Its original content will be retained as a backup.' : '';
                if (confirmText && !window.confirm(confirmText)) return;
                await window.maiaUi.runBusy(button, `${label}...`, async () => {
                    try { await performHistoryAction(name, item); }
                    catch (error) { setStatus(error.message || 'Unable to update history.', true); }
                });
            });
            actions.appendChild(button);
        }
        container.appendChild(actions);
        container.addEventListener('click', (event) => { event.stopPropagation(); selectEntry(container); });
    }
    function appendBackup(container, item) {
        if (!item.backup || typeof item.backup !== 'object') return;
        const content = document.createElement('div'); content.className = 'session-history-backup'; content.hidden = true;
        const body = document.createElement('div'); body.className = 'session-history-backup-content';
        if (item.backup.content !== undefined && item.backup.content !== null) {
            const text = document.createElement('div'); appendText(text, String(item.backup.content), item.backup.contentParts); body.appendChild(text);
        }
        for (const call of item.backup.tool_calls || []) {
            const details = document.createElement('details'); details.className = 'session-history-tool-call';
            const summary = document.createElement('summary'); summary.textContent = `Tool call: ${call.function?.name || 'unknown'}`;
            const pre = document.createElement('pre'); pre.textContent = parseArguments(call.function?.arguments ?? {});
            details.append(summary, pre);

            const outputSection = document.createElement('section'); outputSection.className = 'session-history-original-tool-output';
            const outputLabel = document.createElement('div'); outputLabel.className = 'session-history-original-tool-output-label'; outputLabel.textContent = 'Tool output';
            const outputContent = document.createElement('div'); outputContent.className = 'session-history-original-tool-output-content';
            const resultItem = call?.id
                ? historyItems.find((candidate) => candidate.role === 'tool' && candidate.tool_call_id === call.id)
                : null;
            if (resultItem) {
                const originalResult = resultItem.backup && Object.prototype.hasOwnProperty.call(resultItem.backup, 'content')
                    ? resultItem.backup
                    : resultItem;
                appendText(outputContent, String(originalResult.content ?? ''), originalResult.contentParts);
                if (!outputContent.textContent && !outputContent.childNodes.length) outputContent.textContent = 'Empty response';
            } else {
                outputContent.textContent = 'No matching tool output in the loaded history.';
            }
            outputSection.append(outputLabel, outputContent);
            details.appendChild(outputSection);
            body.appendChild(details);
        }
        if (Object.prototype.hasOwnProperty.call(item.backup, 'data')) {
            const pre = document.createElement('pre'); pre.textContent = JSON.stringify(item.backup.data, null, 2); body.appendChild(pre);
        }
        if (!body.childNodes.length) return;
        content.appendChild(body); container.appendChild(content);
        const toggle = document.createElement('button'); toggle.type = 'button'; toggle.className = 'session-history-backup-toggle'; toggle.textContent = 'Show original';
        toggle.addEventListener('click', () => { content.hidden = !content.hidden; toggle.textContent = content.hidden ? 'Show original' : 'Hide original'; });
        // Only reuse this entry's own metadata row. A tool result can be nested
        // inside an assistant entry and has its own row and original-output toggle.
        let metadata = container.querySelector(':scope > .session-history-metadata');
        if (!metadata) {
            metadata = document.createElement('div'); metadata.className = 'session-history-metadata';
            container.appendChild(metadata);
        }
        metadata.appendChild(toggle);
    }
    function originalToolCall(item, call, callIndex) {
        const originalCalls = item?.backup?.tool_calls;
        if (!Array.isArray(originalCalls)) return null;
        const matchingCall = call?.id
            ? originalCalls.find((candidate) => candidate?.id === call.id)
            : null;
        const candidate = matchingCall || originalCalls[callIndex];
        return candidate?.function ? candidate : null;
    }
    function appendToolCall(container, call, result, item, callIndex = 0) {
        const card = document.createElement('section'); card.className = 'session-history-tool-interaction';
        const header = document.createElement('div'); header.className = 'session-history-tool-header';
        const body = document.createElement('div'); body.className = 'session-history-tool-body';
        const heading = document.createElement('span'); heading.className = 'session-history-tool-heading'; heading.textContent = `Tool call: ${call.function?.name || 'unknown'}`;
        const argsToggle = document.createElement('button'); argsToggle.type = 'button'; argsToggle.className = 'session-history-details-toggle'; argsToggle.textContent = 'show details';
        const details = document.createElement('div'); details.className = 'session-history-tool-details'; details.hidden = true;
        const args = document.createElement('pre'); args.className = 'session-history-tool-arguments'; args.textContent = parseArguments(call.function?.arguments ?? {});
        details.appendChild(args);
        argsToggle.addEventListener('click', (event) => {
            event.stopPropagation(); details.hidden = !details.hidden;
            argsToggle.textContent = details.hidden ? 'show details' : 'hide details';
            argsToggle.setAttribute('aria-expanded', String(!details.hidden));
        });
        argsToggle.setAttribute('aria-expanded', 'false');
        header.append(heading, argsToggle);
        const originalCall = originalToolCall(item, call, callIndex);
        if (originalCall) {
            const originalToggle = document.createElement('button'); originalToggle.type = 'button';
            originalToggle.className = 'session-history-backup-toggle'; originalToggle.textContent = 'Show original input';
            originalToggle.setAttribute('aria-label', 'Show original tool call input');
            const originalInput = document.createElement('pre');
            originalInput.className = 'session-history-original-tool-input';
            originalInput.textContent = parseArguments(originalCall.function.arguments ?? {});
            originalInput.hidden = true;
            originalToggle.addEventListener('click', (event) => {
                event.stopPropagation(); originalInput.hidden = !originalInput.hidden;
                originalToggle.textContent = originalInput.hidden ? 'Show original input' : 'Hide original input';
            });
            details.append(originalToggle, originalInput);
        }
        card.append(header, details);
        if (result) {
            const toggle = document.createElement('button'); toggle.type = 'button'; toggle.className = 'session-history-tool-toggle';
            toggle.textContent = mode === 'groups' ? '▾' : '▸'; toggle.title = mode === 'groups' ? 'Hide tool output' : 'Show tool output';
            toggle.setAttribute('aria-expanded', String(mode === 'groups')); header.prepend(toggle);
            body.hidden = mode !== 'groups';
            toggle.addEventListener('click', (event) => { event.stopPropagation(); body.hidden = !body.hidden; toggle.textContent = body.hidden ? '▸' : '▾'; toggle.title = body.hidden ? 'Show tool output' : 'Hide tool output'; toggle.setAttribute('aria-expanded', String(!body.hidden)); });
            const divider = document.createElement('hr'); divider.className = 'session-history-tool-divider'; body.appendChild(divider);
            const resultNode = document.createElement('div'); resultNode.className = 'session-history-tool-result';
            const output = document.createElement('div'); output.className = 'session-history-tool-output';
            const resultText = String(result.content ?? '');
            if (resultText.trim() || (result.contentParts || []).some((part) => String(part?.text ?? '').trim())) appendText(output, resultText, result.contentParts);
            else { output.textContent = 'Empty response'; output.classList.add('session-history-tool-empty'); }
            resultNode.appendChild(output); appendMetadata(resultNode, result); appendBackup(resultNode, result); appendEntryActions(resultNode, result);
            body.appendChild(resultNode);
        } else {
            const note = document.createElement('div'); note.className = 'session-history-unpaired'; note.textContent = 'No matching result in the loaded history.'; body.appendChild(note);
        }
        card.appendChild(body); card.addEventListener('click', (event) => event.stopPropagation()); container.appendChild(card);
    }
    function renderMessage(item, resultMap, consumed) {
        const article = document.createElement('article');
        const roleName = item.role === 'user' ? 'user' : item.role === 'tool' ? 'tool' : 'assistant';
        article.className = `session-history-message ${roleName}`;
        if (isHidden(item)) article.classList.add('session-history-hidden-entry');
        if (item.role === 'assistant' && Array.isArray(item.tool_calls) && mode !== 'timeline') article.classList.add('grouped-tool-response');
        if (item.role === 'reasoning') {
            article.classList.add('reasoning');
            article.textContent = 'Reasoning';
            return article;
        }
        if (item.role === 'assistant') {
            if (item.content !== null && item.content !== undefined && item.content !== '') {
                const text = document.createElement('div'); appendText(text, String(item.content), item.contentParts); article.appendChild(text);
            }
            if (Array.isArray(item.tool_calls)) {
                for (const [callIndex, call] of item.tool_calls.entries()) {
                    const result = resultMap.get(call?.id)?.find((candidate) => !consumed.has(candidate) && isHidden(candidate) === isHidden(item));
                    if (result && mode !== 'timeline') consumed.add(result);
                    if (mode === 'hidden' && result) continue;
                    appendToolCall(article, call, mode === 'timeline' ? null : result, item, callIndex);
                }
            }
        } else {
            const text = document.createElement('div'); appendText(text, String(item.content ?? ''), item.contentParts); article.appendChild(text);
            if (item.toolUnpairedReason) { const note = document.createElement('div'); note.className = 'session-history-unpaired'; note.textContent = item.toolUnpairedReason; article.appendChild(note); }
        }
        appendMetadata(article, item); appendBackup(article, item); appendEntryActions(article, item);
        return article;
    }
    function appendHistoryEntry(parent, item, resultMap, consumed) {
        parent.appendChild(renderMessage(item, resultMap, consumed));
        if (item.role !== 'user' || item.index === undefined || item.index === null) return;
        const entry = sendEntries.find((candidate) => candidate.userIndex !== null &&
            String(candidate.userIndex) === String(item.index));
        if (entry?.outputNode) parent.appendChild(entry.outputNode);
    }
    function appendPendingSendEntry(entry) {
        if (entry.userIndex !== null) return;
        if (entry.showUser !== false) {
            const user = document.createElement('article');
            user.className = 'session-history-message user session-history-optimistic-user';
            user.textContent = entry.message;
            itemsNode.appendChild(user);
        }
        if (entry.outputNode) itemsNode.appendChild(entry.outputNode);
    }
    function appendPendingSendEntries() {
        for (const entry of sendEntries) appendPendingSendEntry(entry);
    }
    function renderNow() {
        itemsNode.replaceChildren();
        if (!historyItems.length) {
            const empty = document.createElement('p'); empty.className = 'session-history-empty'; empty.textContent = 'No conversation history.'; itemsNode.appendChild(empty);
        }
        const callIds = new Set(); const results = new Map();
        for (const item of historyItems) {
            if (item.role === 'assistant') for (const call of item.tool_calls || []) if (call?.id) callIds.add(call.id);
            if (item.role === 'tool' && item.tool_call_id) { const list = results.get(item.tool_call_id) || []; list.push(item); results.set(item.tool_call_id, list); }
        }
        const consumed = new Set(); let hiddenItems = [];
        const flushHidden = () => {
            if (!hiddenItems.length) return;
            const details = document.createElement('details'); details.className = 'session-history-hidden-group';
            const summary = document.createElement('summary');
            const turns = new Set(hiddenItems.filter((item) => item.role === 'user').map((item) => item.user_index).filter((x) => x !== null && x !== undefined));
            const count = hiddenItems.length;
            summary.textContent = `Show ${count} hidden ${count === 1 ? 'entry' : 'entries'} · ${turns.size || hiddenItems.filter((item) => item.role === 'user').length} turns affected`;
            const contents = document.createElement('div'); contents.className = 'session-history-hidden-items'; details.append(summary, contents); itemsNode.appendChild(details);
            for (const item of hiddenItems) appendHistoryEntry(contents, item, results, consumed);
            hiddenItems = [];
        };
        for (const item of historyItems) {
            if (item.role === 'reasoning' && (mode === 'hidden' || mode === 'collapsed')) continue;
            if (mode === 'hidden') {
                if (item.role === 'tool' && callIds.has(item.tool_call_id)) continue;
                if (item.role === 'assistant' && Array.isArray(item.tool_calls)) {
                    const calls = item.tool_calls.filter((call) => !results.has(call?.id));
                    const hasText = String(item.content ?? '').trim() !== '';
                    if (!hasText && calls.length === 0) continue;
                    const clone = { ...item, tool_calls: calls };
                    if (isHidden(clone)) hiddenItems.push(clone); else { flushHidden(); appendHistoryEntry(itemsNode, clone, results, consumed); }
                    continue;
                }
            }
            if (item.role === 'tool' && mode !== 'timeline' && callIds.has(item.tool_call_id)) {
                if (consumed.has(item)) continue;
                if (mode === 'collapsed' || mode === 'groups') continue;
            }
            const clone = item.role === 'tool' && !callIds.has(item.tool_call_id)
                ? { ...item, toolUnpairedReason: 'No matching call in the loaded history.' } : item;
            if (isHidden(clone)) hiddenItems.push(clone);
            else { flushHidden(); appendHistoryEntry(itemsNode, clone, results, consumed); }
        }
        flushHidden();
        const n = Number(firstIndex);
        if (!historyItems.length || (Number.isInteger(n) && n <= 1)) {
            const start = document.createElement('div'); start.className = 'session-start'; start.textContent = 'Beginning of session'; itemsNode.prepend(start);
        }
        appendPendingSendEntries();
    }
    function render(forceComposer = false, preserveScrollPosition = false) {
        if (selectionIsInHistory()) {
            pendingRender = true;
            return;
        }
        pendingRender = false;
        return preserveViewport(renderNow, forceComposer, preserveScrollPosition);
    }
    function updateHistoryControls() {
        const index = Number(firstIndex);
        const earliestUser = historyItems.filter((item) => item.role === 'user').map((item) => Number(item.user_index)).filter(Number.isInteger);
        const turnsBefore = earliestUser.length ? Math.max(0, Math.min(...earliestUser)) : 0;
        const hasEarlier = earliestUser.length ? turnsBefore > 0 : Number.isInteger(index) && index > 1;
        earlierButton.hidden = !hasEarlier; turnCountControl.hidden = !hasEarlier; allButton.hidden = !hasEarlier; remaining.hidden = !hasEarlier;
        if (hasEarlier) remaining.textContent = `Earlier history: ${Number.isInteger(index) ? Math.max(0, index - 1) : 0} messages · ${turnsBefore} turns`;
    }
    async function load(range = 'turn', { preserve = false } = {}) {
        setStatus('Loading conversation...', false, true);
        try {
            const result = await fetchHistory(range);
            if (preserve) {
                const existing = new Map(historyItems.map((item) => [String(item.index), item]));
                result.items.forEach((item) => existing.set(String(item.index), item));
                historyItems = [...existing.values()].sort((a, b) => Number(a.index) - Number(b.index));
                firstIndex = historyItems[0]?.index ?? result.firstIndex; lastIndex = result.lastIndex;
            } else { historyItems = result.items; firstIndex = result.firstIndex; lastIndex = result.lastIndex; }
            render(); updateHistoryControls(); setStatus('');
            return result;
        } catch (error) { setStatus(error.message || 'Unable to load conversation history.', true); return null; }
    }
    function countToLoad() {
        const clean = turnCount.value.replace(/[^0-9]/g, '').slice(0, 3);
        const count = Math.max(1, Number.parseInt(clean || '1', 10)); turnCount.value = String(count); return count;
    }
    turnCount.addEventListener('input', () => { turnCount.value = turnCount.value.replace(/[^0-9]/g, '').slice(0, 3); });
    async function loadEarlier() {
        if (loadingEarlier) return;
        const userIndexes = historyItems.filter((item) => item.role === 'user').map((item) => Number(item.user_index)).filter(Number.isInteger);
        const earliest = userIndexes.length ? Math.min(...userIndexes) : null;
        if (earliest === null || earliest <= 0) { updateHistoryControls(); return; }
        loadingEarlier = true; turnCount.disabled = true;
        await window.maiaUi.runBusy(earlierButton, 'Loading earlier turns...', async () => {
            setStatus('Loading earlier turns...', false, true);
            try {
                const n = countToLoad(); const low = Math.max(0, earliest - n); const high = earliest - 1;
                const result = await fetchHistory(`turn${low}-turn${high}`);
                const merged = new Map([...result.items, ...historyItems].map((item) => [String(item.index), item]));
                historyItems = [...merged.values()].sort((a, b) => Number(a.index) - Number(b.index));
                firstIndex = result.firstIndex ?? historyItems[0]?.index; lastIndex = historyItems.at(-1)?.index ?? lastIndex;
                render(); updateHistoryControls(); setStatus('');
            } catch (error) { setStatus(error.message || 'Unable to load previous turns.', true); }
        });
        turnCount.disabled = false; loadingEarlier = false; updateHistoryControls();
    }
    async function loadAll() {
        if (loadingEarlier) return;
        loadingEarlier = true;
        await window.maiaUi.runBusy(allButton, 'Loading entire history...', async () => {
            setStatus('Loading entire history...', false, true);
            try { const result = await fetchHistory('all'); historyItems = result.items; firstIndex = result.firstIndex; lastIndex = result.lastIndex; render(); updateHistoryControls(); setStatus(''); }
            catch (error) { setStatus(error.message || 'Unable to load the entire history.', true); }
        });
        loadingEarlier = false;
    }
    async function refresh() {
        const range = Number.isInteger(Number(firstIndex)) ? `${Number(firstIndex)}-` : 'turn';
        const completedSend = activeSend?.completed ? activeSend : null;
        let sendResponseCompleted = false;
        let sendResponsePending = false;
        try {
            // Fetch the last turn after a send so that we can detect history
            // re-indexing instead of assuming the old last index is still valid.
            const result = await fetchHistory(completedSend ? 'turn' : range);
            if (completedSend) {
                if (result.items.length === 0) {
                    completedSend.showUser = completedSend.failed === true;
                    if (completedSend.failed) {
                        render();
                        return { ok: false, pending: true, error: 'The submitted message is not in history yet.' };
                    }
                    if (activeSend === completedSend) activeSend = null;
                    render();
                    const error = 'MAIA returned no history for this send. The session may not have recorded the message.';
                    setStatus(error, true);
                    return { ok: false, error };
                }

                const previousLastIndex = completedSend.baseLastIndex;
                const returnedFirstIndex = Number(result.firstIndex);
                const historyWasRenumbered = previousLastIndex !== null &&
                    (!Number.isInteger(returnedFirstIndex) || returnedFirstIndex !== previousLastIndex + 1);
                if (historyWasRenumbered) {
                    // Old indexes no longer reliably identify the loaded entries.
                    historyItems = result.items;
                } else {
                    const persistedItems = previousLastIndex === null
                        ? []
                        : historyItems.filter((item) => {
                            const index = Number(item.index);
                            return Number.isInteger(index) && index <= previousLastIndex;
                        });
                    historyItems = persistedItems.concat(result.items);
                }
                firstIndex = historyItems.length > 0
                    ? Math.min(...historyItems.map((item) => Number(item.index)).filter(Number.isInteger))
                    : result.firstIndex;
                lastIndex = result.lastIndex;

                // The server may normalize or otherwise change the submitted
                // text. The persisted user entry is authoritative; pair the raw
                // output with the user entry from the returned turn, not by text.
                const sentUser = result.items.find((item) => {
                    if (item.role !== 'user') return false;
                    const itemIndex = Number(item.index);
                    if (completedSend.baseLastIndex !== null && Number.isInteger(itemIndex) &&
                        itemIndex > completedSend.baseLastIndex) return true;
                    const userIndex = Number(item.user_index);
                    if (completedSend.baseLastUserIndex !== null && Number.isInteger(userIndex) &&
                        userIndex > completedSend.baseLastUserIndex) return true;
                    if (completedSend.baseLastIndex === null && completedSend.baseLastUserIndex === null) return true;
                    return String(item.content ?? '') === completedSend.message;
                });
                if (!sentUser) {
                    completedSend.showUser = completedSend.failed === true;
                    if (completedSend.failed) {
                        render();
                        updateHistoryControls();
                        return { ok: false, pending: true, error: 'The submitted message is not in history yet.' };
                    }
                    if (activeSend === completedSend) activeSend = null;
                    render();
                    updateHistoryControls();
                    const error = 'The history was refreshed, but no user message was found for this send. The raw output and message are preserved.';
                    setStatus(error, true);
                    return { ok: false, error };
                }
                completedSend.userIndex = String(sentUser.index);
                const sentUserIndex = Number(sentUser.index);
                sendResponseCompleted = result.items.some((item) => {
                    const itemIndex = Number(item.index);
                    return item.role === 'assistant' && Number.isInteger(itemIndex) &&
                        itemIndex > sentUserIndex && String(item.content ?? '').trim() !== '';
                });
                if (completedSend.outputNode instanceof HTMLDetailsElement) {
                    const selection = document.getSelection();
                    const selectionWithinOutput = selection && !selection.isCollapsed &&
                        (completedSend.outputNode.contains(selection.anchorNode) ||
                            completedSend.outputNode.contains(selection.focusNode));
                    // Keep selected raw output expanded. Explicitly reopen it if
                    // another update collapsed it before this history refresh.
                    if (selectionWithinOutput) completedSend.outputNode.open = true;
                    else completedSend.outputNode.open = false;
                }
                sendResponsePending = completedSend.failed === true && !sendResponseCompleted;
                if (!sendResponsePending && activeSend === completedSend) activeSend = null;
                render();
                updateHistoryControls();
            } else {
                historyItems = result.items;
                firstIndex = result.firstIndex;
                lastIndex = result.lastIndex;
                render();
                updateHistoryControls();
            }
            setStatus('');
            return { ok: true, completed: sendResponseCompleted, pending: sendResponsePending };
        } catch (error) {
            if (completedSend) {
                completedSend.showUser = false;
                render();
            }
            const message = error.message || 'Unable to refresh conversation history.';
            setStatus(message, true);
            return { ok: false, error: message };
        }
    }
    async function wholeHistoryAction(actionName, message) {
        if (!window.confirm(message)) return;
        await withHistoryMutation(async () => {
            setStatus(`${actionName === 'compact' ? 'Compacting' : 'Updating'} history...`, false, true);
            try {
                await window.maiaApi.request('/api/history/action', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({ action:actionName }) });
                await refreshHistoryAfterMutation();
            } catch (error) { setStatus(error.message || 'Unable to update history.', true); }
        });
    }
    function setOptions(select, values, selectedValues, multiple = false) {
        const selected = new Set(Array.isArray(selectedValues) ? selectedValues : [selectedValues ?? '']);
        select.replaceChildren();
        for (const value of [...new Set(['', ...(values || [])])]) {
            const option = document.createElement('option'); option.value = value; option.textContent = value || '(none)'; option.selected = selected.has(value); select.appendChild(option);
        }
        if (!multiple) select.value = String(selectedValues ?? '');
    }
    async function openSettings() {
        const s = role('settings-status'); window.maiaUi.setLoadingStatus(s, 'Loading settings...');
        action('save-settings').disabled = true; settingsDialog.showModal();
        try {
            const result = await window.maiaApi.request('/api/session/settings'); sessionSettings = result;
            setOptions(role('setting-profile'), result.profiles, result.profile);
            setOptions(role('setting-workspace'), result.workspaces, result.workspace);
            setOptions(role('setting-filesets'), result.filesetOptions, result.filesets, true);
            setOptions(role('setting-extra-filesets'), result.filesetOptions, result.extraSendFilesets, true);
            window.maiaUi.setStatus(s, '');
        } catch (error) { window.maiaUi.setStatus(s, error.message || 'Unable to load session settings.', {error:true}); }
        finally { action('save-settings').disabled = false; }
    }
    async function saveSettings() {
        const save = action('save-settings'); await window.maiaUi.runBusy(save, 'Saving settings...', async () => {
            const s = role('settings-status'); window.maiaUi.setLoadingStatus(s, 'Saving settings...');
            const values = (select) => Array.from(select.selectedOptions).map((option) => option.value).filter(Boolean);
            try {
                const result = await window.maiaApi.request('/api/session/settings', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({
                    profile: role('setting-profile').value, workspace: role('setting-workspace').value,
                    filesets: values(role('setting-filesets')), extraSendFilesets: values(role('setting-extra-filesets'))
                }) });
                sessionSettings = result; window.maiaUi.setStatus(s, 'Saved.');
            } catch (error) { window.maiaUi.setStatus(s, error.message || 'Unable to save session settings.', {error:true}); }
        });
    }
    function openRename() { role('rename-name').value = session; role('rename-error').hidden = true; renameDialog.showModal(); role('rename-name').focus(); role('rename-name').select(); }
    function openCopy() { role('copy-name').value = `${session}-copy`; role('copy-error').hidden = true; copyDialog.showModal(); role('copy-name').focus(); role('copy-name').select(); }
    function navigateSession(name) { window.location.assign(`${basePath}/session/${encodeURIComponent(name)}`); }
    async function saveRename() {
        const newName = role('rename-name').value.trim(); const errorNode = role('rename-error'); errorNode.hidden = true;
        await window.maiaUi.runBusy(action('save-rename'), 'Renaming session...', async () => {
            try { await window.maiaApi.request('/api/session/rename', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({oldName:session,newName})}); navigateSession(newName); }
            catch (error) { errorNode.textContent = error.message || 'Unable to rename session.'; errorNode.hidden = false; }
        });
    }
    async function saveCopy() {
        const name = role('copy-name').value.trim(); const errorNode = role('copy-error'); errorNode.hidden = true;
        await window.maiaUi.runBusy(action('save-copy'), 'Copying session...', async () => {
            try { await window.maiaApi.request('/api/session/create', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name,source:session})}); navigateSession(name); }
            catch (error) { errorNode.textContent = error.message || 'Unable to copy session.'; errorNode.hidden = false; }
        });
    }
    async function deleteSession() {
        if (!window.confirm(`Permanently delete session “${session}”? Its history and other session data will be removed and cannot be recovered.`)) return;
        setStatus('Deleting session...', false, true);
        try { await window.maiaApi.request('/api/session/delete', {method:'POST',headers:{'Content-Type':'text/plain; charset=utf-8'},body:session}); window.location.assign(`${basePath}/`); }
        catch (error) { setStatus(error.message || 'Unable to delete session.', true); }
    }
    const toolMenu = window.maiaActionMenu.create({
        triggerIcon:'\u25EB', triggerText:'Tool view', ariaLabel:'Tool history display options', title:'Tool history display options',
        menuLabel:'Tool history display', wrapperClassName:'session-history-menu-wrapper',
        items:() => [
            {type:'radio',label:'Timeline',checked:mode === 'timeline',run:() => setMode('timeline')},
            {type:'radio',label:'Expanded',checked:mode === 'groups',run:() => setMode('groups')},
            {type:'radio',label:'Hidden',checked:mode === 'hidden',run:() => setMode('hidden')},
            {type:'radio',label:'Collapsed',checked:mode === 'collapsed',run:() => setMode('collapsed')}
        ]
    });
    role('tool-view-menu').appendChild(toolMenu);
    const sessionMenu = window.maiaActionMenu.create({
        triggerIcon:'☰', triggerText:'Session & history', ariaLabel:'Session and history operations', title:'Session and history operations',
        menuLabel:'Session and history operations', wrapperClassName:'session-history-menu-wrapper', floatingMenuClass:'session-history-session-menu',
        items:() => [
            {icon:'↻',label:'Refresh history',run:refresh},
            {icon:'⧉',label:'Copy session',run:openCopy},
            {icon:'✎',label:'Rename session',run:openRename},
            {icon:'⚙︎',label:'Session settings',run:openSettings},
            {type:'separator'},
            {icon:'≋↕',label:'Compact history',danger:false,run:() => wholeHistoryAction('compact','Compact the conversation history? The original entries will be retained as hidden summarized history.')},
            {icon:'⌧↕',label:'Delete history',danger:true,run:() => wholeHistoryAction('clear','Clear the entire history? This cannot be undone.')},
            {icon:'⊘↕',label:'Hide history',run:() => wholeHistoryAction('hide-all','Hide the entire history? It can be unhidden later.')},
            {icon:'⊘',label:'Hide last turn',run:() => wholeHistoryAction('hide-turn','Hide the last turn? It can be unhidden later.')},
            {type:'separator'},
            {icon:'×',label:'Delete session',danger:true,run:deleteSession}
        ], onError:(error) => setStatus(error.message || 'Unable to perform session action.',true)
    });
    role('session-menu').appendChild(sessionMenu);
    function setMode(next) { if (!['timeline','groups','hidden','collapsed'].includes(next)) return; mode = next; render(); }
    action('earlier').addEventListener('click', loadEarlier);
    action('all').addEventListener('click', loadAll);
    root.querySelector('[data-history-form="edit"]').addEventListener('submit', async (event) => {
        if (event.submitter?.value !== 'save') return; event.preventDefault();
        const button = action('save-edit'); const errorNode = role('edit-error'); errorNode.hidden = true;
        await window.maiaUi.runBusy(button, 'Saving entry...', async () => {
            try { await performHistoryAction('replace',{index:editDialog.dataset.index},role('edit-content').value); editDialog.close('saved'); }
            catch (error) { errorNode.textContent = error.message || 'Unable to replace history entry.'; errorNode.hidden = false; }
        });
    });
    root.querySelector('[data-history-form="settings"]').addEventListener('submit', (event) => { if (event.submitter?.value === 'save') { event.preventDefault(); saveSettings(); } });
    root.querySelector('[data-history-form="rename"]').addEventListener('submit', (event) => { if (event.submitter?.value === 'rename') { event.preventDefault(); saveRename(); } });
    root.querySelector('[data-history-form="copy"]').addEventListener('submit', (event) => { if (event.submitter?.value === 'copy') { event.preventDefault(); saveCopy(); } });
    window.addEventListener('maia:send-start', (event) => {
        activeSend = {
            message: String(event.detail?.message ?? ''),
            outputNode: event.detail?.outputNode instanceof HTMLElement ? event.detail.outputNode : null,
            baseLastIndex: lastIndex === null || lastIndex === undefined || !Number.isInteger(Number(lastIndex))
                ? null
                : Number(lastIndex),
            baseLastUserIndex: historyItems.reduce((latest, item) => {
                const index = Number(item.user_index);
                return item.role === 'user' && Number.isInteger(index)
                    ? (latest === null ? index : Math.max(latest, index))
                    : latest;
            }, null),
            userIndex: null,
            showUser: true,
            completed: false,
        };
        sendEntries.push(activeSend);
        setStatus('');
        if (selectionIsInHistory()) {
            pendingRender = true;
            appendPendingSendEntry(activeSend);
        } else {
            render(true);
        }
    });
    window.addEventListener('maia:send-chunk', () => {
        // Streaming output updates are viewport-preserving in the composer component.
    });
    window.addEventListener('maia:send-complete', () => {
        if (!activeSend) return;
        activeSend.completed = true;
    });
    window.addEventListener('maia:send-failure', (event) => {
        const error = String(event.detail?.error ?? 'Unable to send the message.');
        if (activeSend) {
            activeSend.completed = true;
            activeSend.failed = true;
            // Keep the submitted text beside its raw error output if the server
            // did not persist a corresponding user history entry.
            activeSend.showUser = true;
        }
        setStatus(error, true);
    });
    window.addEventListener('maia:history-refresh', (event) => {
        void refresh().then((result) => event.detail?.done?.(result)).catch((error) =>
            event.detail?.done?.({ ok: false, error: error.message || 'Unable to refresh conversation history.' })
        );
    });
    turnCount.addEventListener('keydown', (event) => { if (event.key === 'Enter') { event.preventDefault(); loadEarlier(); } });
    load('turn');
})();
