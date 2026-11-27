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
    let historyActionQueue = [];
    let historyActionQueueRunning = false;
    let historyMutationRevision = 0;
    let selectedHistoryIndex = null;
    let pendingRender = false;
    const timelineEntries = [];
    const messageViewModes = new Map();
    const actionContainers = new Set();
    const actionToolbarStates = new Map();
    const floatingCandidates = new Set();
    const actionToolbarTargets = new WeakMap();
    let activeFloatingState = null;
    let actionResizeObserver = null;
    let floatingEntryActionsFrame = 0;
    if (typeof ResizeObserver === 'function') {
        actionResizeObserver = new ResizeObserver((entries) => {
            for (const observed of entries) updateEntryActionSize(observed.target);
        });
    }
    let actionVisibilityObserver = null;
    if (typeof IntersectionObserver === 'function') {
        actionVisibilityObserver = new IntersectionObserver((entries) => {
            for (const observed of entries) {
                const state = actionToolbarTargets.get(observed.target);
                if (!state) continue;
                if (observed.target === state.bottomActions) state.bottomVisible = observed.isIntersecting;
                if (observed.target === state.container) state.containerVisible = observed.isIntersecting;
                syncFloatingCandidate(state);
            }
            scheduleFloatingEntryActions();
        });
    }
    function floatingBarAnchorY() {
        return 56;
    }
    function contentIsUnderFloatingBar(state) {
        if (!state.contentTarget || !state.contentTarget.isConnected) return false;
        const rect = state.contentTarget.getBoundingClientRect();
        const anchorY = floatingBarAnchorY();
        return rect.top <= anchorY && rect.bottom > anchorY;
    }
    function syncFloatingCandidate(state) {
        if (state.container.isConnected &&
            state.container.classList.contains('session-history-entry-tall') &&
            state.containerVisible && !state.bottomVisible) {
            floatingCandidates.add(state);
        } else {
            floatingCandidates.delete(state);
        }
    }
    function scheduleFloatingEntryActions() {
        if (floatingEntryActionsFrame) return;
        floatingEntryActionsFrame = window.requestAnimationFrame(() => {
            floatingEntryActionsFrame = 0;
            updateFloatingEntryActions();
        });
    }
    function updateFloatingEntryActions() {
        const eligible = Array.from(floatingCandidates);
        const toolOutputUnderBar = eligible.find((state) =>
            state.targetKind === 'tool' && contentIsUnderFloatingBar(state));
        let nextState = toolOutputUnderBar;
        if (!nextState) {
            nextState = eligible.find((state) =>
                state.targetKind === 'assistant' && contentIsUnderFloatingBar(state));
        }
        if (!nextState) nextState = eligible.find((state) => state.targetKind === 'assistant');
        if (!nextState) nextState = eligible.find((state) => state.targetKind === 'tool');
        if (nextState === activeFloatingState) return;
        if (activeFloatingState) {
            activeFloatingState.floatingActions.hidden = true;
            activeFloatingState.container.classList.remove('session-history-entry-actions-floating-visible');
        }
        activeFloatingState = nextState || null;
        if (activeFloatingState) {
            activeFloatingState.floatingActions.hidden = false;
            activeFloatingState.container.classList.add('session-history-entry-actions-floating-visible');
        }
    }
    function updateEntryActionSize(container) {
        const state = actionToolbarStates.get(container) || actionToolbarTargets.get(container);
        if (!state || !state.container.isConnected) return;
        let targetHeight = 0;
        if (state.sizeTarget && state.sizeTarget.isConnected) {
            targetHeight = state.sizeTarget.getBoundingClientRect().height;
        }
        state.container.classList.toggle('session-history-entry-tall', targetHeight > window.innerHeight);
        syncFloatingCandidate(state);
        scheduleFloatingEntryActions();
    }
    function updateAllEntryActionSizes() {
        for (const container of actionContainers) updateEntryActionSize(container);
    }
    window.addEventListener('resize', updateAllEntryActionSizes);
    window.addEventListener('scroll', scheduleFloatingEntryActions, { passive: true });

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
    function dispatch(name, detail = {}) {
        window.dispatchEvent(new CustomEvent(name, { detail }));
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
    function isSticky(item) { return item?.sticky === true || item?.sticky === 1 || item?.sticky === 'true'; }
    function isRetained(item) { return item?.retain === true || item?.retain === 1 || item?.retain === 'true'; }
    function loadedHistoryRange() {
        const hasFirst = firstIndex !== null && firstIndex !== undefined && firstIndex !== '' && Number.isInteger(Number(firstIndex));
        const hasLast = lastIndex !== null && lastIndex !== undefined && lastIndex !== '' && Number.isInteger(Number(lastIndex));
        if (hasFirst && hasLast) return `${Number(firstIndex)}-${Number(lastIndex)}`;
        // An incomplete range must not become an open-ended request, which can
        // unintentionally reload all history after a mutation.
        return 'turn';
    }
    function updateLocalHistoryFlag(actionName, item) {
        if (!['sticky', 'unsticky', 'retain', 'unretain'].includes(actionName)) return;
        const flag = actionName === 'sticky' || actionName === 'unsticky' ? 'sticky' : 'retain';
        const enabled = actionName === 'sticky' || actionName === 'retain';
        const relatedCallIds = new Set(item.role === 'assistant'
            ? (item.tool_calls || []).map((call) => call?.id).filter(Boolean)
            : (item.role === 'tool' && item.tool_call_id ? [item.tool_call_id] : []));
        const update = (candidate) => {
            const related = String(candidate.index) === String(item.index) ||
                (candidate.role === 'tool' && relatedCallIds.has(candidate.tool_call_id)) ||
                (candidate.role === 'assistant' && (candidate.tool_calls || []).some((call) => relatedCallIds.has(call?.id)));
            if (!related) return;
            if (enabled) candidate[flag] = true;
            else delete candidate[flag];
        };
        historyItems.forEach(update);
        timelineEntries.forEach((entry) => {
            if (entry.kind === 'history') update(entry.item);
        });
    }
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
    const changeReferencePattern = /\b(?:proposal\s+created|change\s+id)\s*:\s*([A-Za-z0-9_.+-]+)/gi;
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
        const timestamp = typeof item.timestamp === 'string' ? item.timestamp : '';
        const hidden = isHidden(item);
        const sticky = isSticky(item);
        const retained = isRetained(item);
        if (timestamp === '' && !hidden && !sticky && !retained) return;
        const node = document.createElement('div'); node.className = 'session-history-metadata';
        if (timestamp !== '') {
            const time = document.createElement('time');
            time.dateTime = timestamp;
            time.textContent = formatTimestamp(timestamp);
            time.title = timestamp;
            node.appendChild(time);
        }
        if (hidden) {
            const badge = document.createElement('span');
            badge.className = 'session-history-flag-badge hidden';
            badge.textContent = 'Hidden from AI';
            node.appendChild(badge);
        }
        if (sticky) {
            const badge = document.createElement('span');
            badge.className = 'session-history-flag-badge sticky';
            badge.textContent = 'Sticky';
            node.appendChild(badge);
        }
        if (retained) {
            const badge = document.createElement('span');
            badge.className = 'session-history-flag-badge retained';
            badge.textContent = 'Retained';
            node.appendChild(badge);
        }
        parent.appendChild(node);
    }
    function selectEntry(element) {
        itemsNode.querySelectorAll('.session-history-entry-selected').forEach((node) => node.classList.remove('session-history-entry-selected'));
        element?.classList.add('session-history-entry-selected');
        const indexedEntry = element?.matches('[data-history-index]') ? element : element?.closest('[data-history-index]');
        if (indexedEntry?.dataset.historyIndex !== undefined) selectedHistoryIndex = indexedEntry.dataset.historyIndex;
    }
    async function fetchHistory(range, signal, { includeSticky = true, stickyOnly = false } = {}) {
        const requestItems = async (query, body) => {
            const result = await window.maiaApi.request(`/api/history/show${query}`, {
                method: 'POST', headers: { 'Content-Type': 'text/plain; charset=utf-8' }, body, signal
            });
            // New API responses stream the CLI's JSON array directly to avoid
            // duplicating large history payloads in PHP memory. Accept the old
            // envelope too during rolling deployments.
            const items = Array.isArray(result) ? result : result?.items;
            if (!Array.isArray(items)) throw new Error('MAIA returned invalid history items.');
            return { result: Array.isArray(result) ? null : result, items };
        };
        const requested = await requestItems(stickyOnly ? '?stickyOnly=1' : '', range);
        const base = requested.result || {
            ok: true,
            range,
            firstIndex: requested.items[0]?.index ?? null,
            lastIndex: requested.items.at(-1)?.index ?? null,
            firstId: requested.items[0]?.id ?? null,
            lastId: requested.items.at(-1)?.id ?? null,
            rangeItemCount: requested.items.length
        };
        base.items = requested.items;
        if (stickyOnly || !includeSticky) return base;

        const sticky = await requestItems('?stickyOnly=1', '');
        const merged = new Map(requested.items.map((item) => [String(item.index), item]));
        for (const item of sticky.items) merged.set(String(item.index), item);
        return {
            ...base,
            items: [...merged.values()].sort((first, second) => Number(first.index) - Number(second.index))
        };
    }
    async function refreshHistoryAfterMutation({ preserveLoadedItems = false } = {}) {
        // Refresh only the non-sticky range already loaded. The API adds sticky
        // entries outside that range, so there is no need to fetch all history.
        const previouslyLoaded = historyItems;
        const result = await fetchHistory(loadedHistoryRange());
        if (preserveLoadedItems) {
            // If a sticky item outside the current range is made unsticky, keep
            // it in this already-open view. It will naturally disappear on a
            // later ordinary history load unless it is sticky again.
            const merged = new Map(previouslyLoaded.map((item) => [String(item.index), item]));
            result.items.forEach((item) => merged.set(String(item.index), item));
            historyItems = [...merged.values()].sort((a, b) => Number(a.index) - Number(b.index));
        } else {
            historyItems = result.items;
        }
        firstIndex = result.firstIndex;
        lastIndex = result.lastIndex;
        reconcileTimeline(historyItems, true);
        render(); updateHistoryControls(); setStatus('');
    }
    function updateHistoryActionStatus() {
        const actionCount = historyActionQueue.length + (historyActionQueueRunning ? 1 : 0);
        if (actionCount === 0) {
            dispatch('maia:history-operation-status', { busy:false });
            return;
        }
        const message = actionCount > 1
            ? `Updating history (${actionCount} actions)...`
            : 'Updating history...';
        dispatch('maia:history-operation-status', { busy:true, message, loading:true });
    }
    async function drainHistoryActionQueue() {
        if (historyActionQueueRunning) return;
        historyActionQueueRunning = true;
        updateHistoryActionStatus();
        const completedJobs = [];
        let refreshError = null;
        try {
            await withHistoryMutation(async () => {
                let changed = false;
                let preserveLoadedItems = true;
                while (historyActionQueue.length > 0) {
                    const job = historyActionQueue.shift();
                    updateHistoryActionStatus();
                    try {
                        const body = { action: job.actionName, index: Number(job.item.index) };
                        if (job.actionName === 'prune' || job.actionName === 'cut') {
                            body.role = job.item.role;
                            body.roleIndex = Number(job.item[`${job.item.role}_index`]);
                        }
                        if (job.actionName === 'replace') body.content = job.content ?? '';
                        await window.maiaApi.request('/api/history/action', {
                            method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body)
                        });
                        const flagAction = ['sticky', 'unsticky', 'retain', 'unretain'].includes(job.actionName);
                        if (flagAction) updateLocalHistoryFlag(job.actionName, job.item);
                        else preserveLoadedItems = false;
                        changed = true;
                        completedJobs.push({ job, error: null });
                    } catch (error) {
                        completedJobs.push({ job, error });
                    }
                }
                if (changed) await refreshHistoryAfterMutation({ preserveLoadedItems });
            });
        } catch (error) {
            refreshError = error;
        } finally {
            historyActionQueueRunning = false;
            for (const { job, error } of completedJobs) {
                const finalError = error || refreshError;
                if (finalError) job.reject(finalError);
                else job.resolve();
            }
            if (refreshError) {
                dispatch('maia:history-operation-status', {
                    busy:false,
                    message:refreshError.message || 'Unable to refresh updated history.',
                    error:true
                });
            }
            updateHistoryActionStatus();
            if (historyActionQueue.length > 0) void drainHistoryActionQueue();
        }
    }
    function performHistoryAction(actionName, item, content = null) {
        historyMutationRevision += 1;
        selectedHistoryIndex = String(item.index);
        return new Promise((resolve, reject) => {
            historyActionQueue.push({ actionName, item, content, resolve, reject });
            updateHistoryActionStatus();
            void drainHistoryActionQueue();
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
        let entryDescription = 'history entry';
        if (item.role === 'user') {
            entryDescription = 'user message';
        } else if (item.role === 'assistant') {
            entryDescription = 'assistant response';
        } else if (item.role === 'tool') {
            entryDescription = 'tool result';
        }
        const defs = [
            [isSticky(item) ? 'unsticky' : 'sticky', isSticky(item) ? '★' : '☆', isSticky(item) ? 'Remove sticky' : 'Make sticky'],
            [isRetained(item) ? 'unretain' : 'retain', isRetained(item) ? '▣' : '□', isRetained(item) ? 'Stop keeping in history' : 'Keep in history'],
            ['copy-content', '\u29C9', `Copy ${entryDescription} content`],
            ['edit', '✎', `Edit ${entryDescription}`],
            [isHidden(item) ? 'unhide' : 'hide', isHidden(item) ? '⊙' : '⊘', `${isHidden(item) ? 'Unhide' : 'Hide'} ${entryDescription}`],
            ['prune', '≋', `Reduce ${entryDescription}`], ['cut', '⌧', `Clear ${entryDescription}`],
            ['delete', '×', `Delete ${entryDescription}`], ['delete-below', '×↓', `Delete ${entryDescription} and all below`]
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
            if (item.role === 'tool' && matchingCalls.length && ['hide', 'delete', 'delete-below', 'sticky', 'unsticky', 'retain', 'unretain'].includes(name)) {
                button.disabled = true; button.title = 'Manage this tool result through its assistant tool call.'; button.setAttribute('aria-label', button.title);
            } else if (name === 'hide' && isRetained(item)) {
                button.disabled = true; button.title = 'Stop keeping this entry in history before hiding it.'; button.setAttribute('aria-label', button.title);
            } else if (name === 'retain' && isHidden(item)) {
                button.disabled = true; button.title = 'Unhide this entry before keeping it in history.'; button.setAttribute('aria-label', button.title);
            } else if (item.role === 'tool' && name === 'unhide' && (!matchingCalls.length || matchingCalls.every(isHidden))) {
                button.disabled = true; button.title = matchingCalls.length ? 'Unhide the assistant tool call first.' : 'This tool result has no matching assistant tool call.'; button.setAttribute('aria-label', button.title);
            }
            button.addEventListener('click', async (event) => {
                event.stopPropagation();
                if (['sticky', 'unsticky', 'retain', 'unretain'].includes(name)) {
                    // Keep the clicked history item selected across the queued
                    // mutation and the single refresh performed when the queue drains.
                    selectedHistoryIndex = String(item.index);
                    document.getSelection()?.removeAllRanges();
                }
                if (name === 'copy-content') {
                    try {
                        await navigator.clipboard.writeText(String(item.content ?? ''));
                        setStatus(`${entryDescription[0].toUpperCase()}${entryDescription.slice(1)} content copied.`);
                    } catch (error) {
                        setStatus(error.message || 'Unable to copy content to the clipboard.', true);
                    }
                    return;
                }
                if (name === 'edit') {
                    editDialog.dataset.index = String(item.index);
                    role('edit-content').value = String(item.content ?? '');
                    role('edit-error').hidden = true; editDialog.showModal(); role('edit-content').focus(); return;
                }
                let confirmText = '';
                if (name === 'delete-below') {
                    confirmText = `Delete ${entryDescription} and all history entries below it? This cannot be undone.`;
                } else if (name === 'delete') {
                    confirmText = `Delete ${entryDescription}? This cannot be undone.`;
                } else if (name === 'cut') {
                    confirmText = `Clear ${entryDescription}? Its original content will be retained as a backup.`;
                } else if (name === 'prune') {
                    confirmText = `Reduce ${entryDescription}? Its original content will be retained as a backup.`;
                }
                if (confirmText && !await window.maiaUi.confirmAction({
                    title: label,
                    message: confirmText,
                    actionLabel: label,
                    actionType: ['delete', 'delete-below'].includes(name) ? 'action-warning' : 'action-normal'
                })) return;
                await window.maiaUi.runBusy(button, `${label}...`, async () => {
                    try { await performHistoryAction(name, item); }
                    catch (error) { setStatus(error.message || 'Unable to update history.', true); }
                });
            });
            actions.appendChild(button);
        }
        actions.classList.add('session-history-entry-actions-bottom');
        container.appendChild(actions);
        if (item.role === 'assistant' || item.role === 'tool') {
            const floatingActions = actions.cloneNode(true);
            floatingActions.classList.remove('session-history-entry-actions-bottom');
            floatingActions.classList.add('session-history-entry-actions-floating');
            const targetLabel = item.role === 'tool' ? 'tool output' : 'assistant response';
            floatingActions.setAttribute('aria-label', `Actions for ${targetLabel}`);
            floatingActions.title = `Actions for ${targetLabel}`;
            for (const button of floatingActions.querySelectorAll('button.session-history-entry-action')) {
                button.title = `${button.title} (${targetLabel})`;
                button.setAttribute('aria-label', `${button.getAttribute('aria-label')} (${targetLabel})`);
            }
            floatingActions.hidden = true;
            const proxyClick = (toolbar) => {
                toolbar.addEventListener('click', (event) => {
                    event.stopPropagation();
                    if (!(event.target instanceof Element)) return;
                    const button = event.target.closest('button.session-history-entry-action');
                    if (!button) return;
                    const sourceButtons = Array.from(toolbar.querySelectorAll('button.session-history-entry-action'));
                    const bottomButtons = Array.from(actions.querySelectorAll('button.session-history-entry-action'));
                    const buttonIndex = sourceButtons.indexOf(button);
                    const bottomButton = bottomButtons[buttonIndex];
                    if (bottomButton && !bottomButton.disabled) bottomButton.click();
                });
            };
            proxyClick(floatingActions);
            container.appendChild(floatingActions);

            actionContainers.add(container);
            const messageContent = container.querySelector(':scope > .session-history-message-content');
            const toolOutput = container.querySelector(':scope > .session-history-tool-output');
            let contentTarget = null;
            if (item.role === 'assistant') {
                contentTarget = messageContent;
            } else {
                contentTarget = toolOutput;
            }
            const state = {
                container,
                targetKind: item.role === 'tool' ? 'tool' : 'assistant',
                contentTarget,
                sizeTarget: contentTarget,
                bottomActions: actions,
                floatingActions,
                bottomVisible: false,
                containerVisible: false
            };
            actionToolbarStates.set(container, state);
            actionToolbarTargets.set(actions, state);
            actionToolbarTargets.set(container, state);
            if (state.sizeTarget) actionToolbarTargets.set(state.sizeTarget, state);
            if (actionVisibilityObserver) {
                actionVisibilityObserver.observe(actions);
                actionVisibilityObserver.observe(container);
            }
            if (actionResizeObserver && state.sizeTarget) {
                // Only observe the measured content. Observing the container too
                // creates a ResizeObserver feedback path: toggling its action
                // classes changes container size and immediately retriggers us.
                actionResizeObserver.observe(state.sizeTarget);
            }
            updateEntryActionSize(container);
        }
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
        if (result.index !== undefined && result.index !== null) resultNode.dataset.historyIndex = String(result.index);
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
    function assistantResponseKey(item) {
        if (item.id !== undefined && item.id !== null) {
            const timestamp = String(item.timestamp ?? '');
            return `id:${String(item.id)}:${timestamp}`;
        }
        if (item.timestamp) return `timestamp:${String(item.timestamp)}`;
        return `index:${String(item.index ?? '')}`;
    }
    function lastAssistantOutputKey() {
        for (let index = timelineEntries.length - 1; index >= 0; index -= 1) {
            const entry = timelineEntries[index];
            if (entry.kind !== 'history' || entry.item?.role !== 'assistant') continue;
            if (String(entry.item.content ?? '').trim() !== '') return assistantResponseKey(entry.item);
        }
        return '';
    }
    function renderMessageContent(container, item, viewMode) {
        const content = String(item.content ?? '');
        container.replaceChildren();
        container.classList.remove('session-history-message-markdown');
        if (viewMode === 'raw') {
            const pre = document.createElement('pre');
            pre.className = 'session-history-message-raw';
            pre.textContent = content;
            container.appendChild(pre);
        } else if (viewMode === 'markdown') {
            if (!window.maiaMarkdown || typeof window.maiaMarkdown.render !== 'function') {
                container.textContent = 'Markdown rendering is unavailable.';
            } else {
                container.classList.add('session-history-message-markdown');
                container.appendChild(window.maiaMarkdown.render(content));
            }
        } else {
            appendText(container, content, item.contentParts);
        }
    }
    function appendMessageViewControls(article, item, roleName) {
        const key = `${roleName}:${assistantResponseKey(item)}`;
        let viewMode = messageViewModes.get(key) || 'markdown';
        const toolbar = document.createElement('div');
        toolbar.className = 'session-history-message-view-controls';
        toolbar.setAttribute('role', 'group');
        toolbar.setAttribute('aria-label', `${roleName === 'assistant' ? 'Assistant response' : 'User message'} display`);
        const contentContainer = document.createElement('div');
        contentContainer.className = 'session-history-message-content';
        if (roleName === 'assistant' && assistantResponseKey(item) === lastAssistantOutputKey()) {
            article.classList.add('session-history-last-assistant-output');
        }
        const choices = [
            { value: 'text', label: 'Text' },
            { value: 'raw', label: 'Raw' },
            { value: 'markdown', label: 'Markdown' }
        ];
        for (const choice of choices) {
            const button = document.createElement('button');
            button.type = 'button';
            button.textContent = choice.label;
            button.setAttribute('aria-pressed', String(viewMode === choice.value));
            button.addEventListener('click', (event) => {
                event.stopPropagation();
                viewMode = choice.value;
                messageViewModes.set(key, viewMode);
                for (const sibling of toolbar.querySelectorAll('button')) {
                    sibling.setAttribute('aria-pressed', String(sibling === button));
                }
                renderMessageContent(contentContainer, item, viewMode);
            });
            toolbar.appendChild(button);
        }
        article.append(toolbar, contentContainer);
        renderMessageContent(contentContainer, item, viewMode);
    }
    function renderMessage(item, resultMap, consumed) {
        const article = document.createElement('article');
        const roleName = item.role === 'user' ? 'user' : item.role === 'tool' ? 'tool' : 'assistant';
        article.className = `session-history-message ${roleName}`;
        if (isHidden(item)) article.classList.add('session-history-hidden-entry');
        if (isSticky(item)) article.classList.add('session-history-sticky-entry');
        if (isRetained(item)) article.classList.add('session-history-retained-entry');
        if (item.role === 'assistant' && Array.isArray(item.tool_calls) && mode !== 'timeline') article.classList.add('grouped-tool-response');
        if (item.role === 'reasoning') {
            article.classList.add('reasoning');
            article.textContent = 'Reasoning';
            return article;
        }
        if (item.role === 'assistant') {
            if (item.content !== null && item.content !== undefined && item.content !== '') {
                appendMessageViewControls(article, item, 'assistant');
            }
            if (Array.isArray(item.tool_calls)) {
                for (const [callIndex, call] of item.tool_calls.entries()) {
                    const result = resultMap.get(call?.id)?.find((candidate) => !consumed.has(candidate) && isHidden(candidate) === isHidden(item));
                    if (result && mode !== 'timeline') consumed.add(result);
                    if (mode === 'hidden' && result) continue;
                    appendToolCall(article, call, mode === 'timeline' ? null : result, item, callIndex);
                }
            }
        } else if (item.role === 'user') {
            if (String(item.content ?? '') !== '') appendMessageViewControls(article, item, 'user');
        } else {
            const text = document.createElement('div'); appendText(text, String(item.content ?? ''), item.contentParts); article.appendChild(text);
            if (item.toolUnpairedReason) { const note = document.createElement('div'); note.className = 'session-history-unpaired'; note.textContent = item.toolUnpairedReason; article.appendChild(note); }
        }
        appendMetadata(article, item); appendBackup(article, item); appendEntryActions(article, item);
        return article;
    }
    function historyItemsMatch(existing, incoming) {
        if (existing.role !== incoming.role) return false;
        if (existing.id !== undefined && existing.id !== null && incoming.id !== undefined && incoming.id !== null) {
            if (String(existing.id) !== String(incoming.id)) return false;
            if (existing.timestamp && incoming.timestamp && existing.timestamp !== incoming.timestamp) return false;
            return true;
        }
        if (existing.timestamp && incoming.timestamp && existing.timestamp === incoming.timestamp) {
            if (existing.role === 'tool' && existing.tool_call_id !== incoming.tool_call_id) return false;
            return true;
        }
        if (Number(existing.index) !== Number(incoming.index)) return false;
        if (existing.role === 'tool' && existing.tool_call_id !== incoming.tool_call_id) return false;
        return String(existing.content ?? '') === String(incoming.content ?? '');
    }
    function bindOptimisticUser(send, user) {
        const entry = send?.userTimelineEntry;
        if (!entry || entry.kind !== 'optimistic-user') return;
        entry.kind = 'history';
        entry.item = user;
        entry.bound = true;
        entry.visible = true;
    }
    function reconcileTimeline(items, removeMissing = false, prependNew = false) {
        const existingHistory = timelineEntries.filter((entry) => entry.kind === 'history');
        const matched = new Set();
        const newEntries = [];
        const seenIncoming = new Set();
        for (const item of items) {
            const indexKey = item.index === undefined || item.index === null ? '' : String(item.index);
            const incomingKey = indexKey !== '' ? `index:${indexKey}` :
                `${item.role}:${String(item.id ?? '')}:${String(item.timestamp ?? '')}:${String(item.content ?? '')}`;
            if (seenIncoming.has(incomingKey)) continue;
            seenIncoming.add(incomingKey);

            // History indices are the authoritative identity for an entry in a
            // single conversation snapshot. Prefer them so metadata-only updates
            // replace the existing timeline item instead of appending a copy.
            let entry = indexKey !== ''
                ? existingHistory.find((candidate) => !matched.has(candidate) &&
                    String(candidate.item?.index ?? '') === indexKey)
                : null;
            if (!entry) {
                entry = existingHistory.find((candidate) => !matched.has(candidate) &&
                    historyItemsMatch(candidate.item, item));
            }
            if (!entry && item.role === 'user') {
                const optimisticEntries = timelineEntries.filter((candidate) =>
                    candidate.kind === 'optimistic-user' && candidate.visible !== false &&
                    !candidate.bound && String(candidate.item.content ?? '') === String(item.content ?? ''));
                if (optimisticEntries.length > 0) {
                    entry = optimisticEntries[optimisticEntries.length - 1];
                    entry.kind = 'history';
                    entry.bound = true;
                }
            }
            if (entry) {
                entry.item = item;
                matched.add(entry);
            } else {
                newEntries.push({ kind: 'history', item });
            }
        }

        // Deduplicate any pre-existing duplicate history entries as well. Keep
        // non-history timeline entries (notably live raw-output DOM nodes) intact.
        const retained = new Set();
        for (let position = timelineEntries.length - 1; position >= 0; position -= 1) {
            const entry = timelineEntries[position];
            if (entry.kind !== 'history') continue;
            const key = entry.item?.index === undefined || entry.item?.index === null
                ? `${entry.item?.role}:${String(entry.item?.id ?? '')}:${String(entry.item?.timestamp ?? '')}:${String(entry.item?.content ?? '')}`
                : `index:${String(entry.item.index)}`;
            if (retained.has(key) || (removeMissing && !matched.has(entry))) {
                timelineEntries.splice(position, 1);
            } else {
                retained.add(key);
            }
        }

        // Insert new history entries in index order before live/optimistic tail
        // entries, rather than blindly appending below them or duplicating them.
        newEntries.sort((a, b) => Number(a.item.index ?? 0) - Number(b.item.index ?? 0));
        for (const entry of newEntries) {
            const itemIndex = Number(entry.item.index);
            let position = timelineEntries.findIndex((candidate) =>
                candidate.kind === 'history' && Number(candidate.item?.index) > itemIndex);
            if (position < 0) {
                position = timelineEntries.findIndex((candidate) => candidate.kind !== 'history');
            }
            if (position < 0) timelineEntries.push(entry);
            else timelineEntries.splice(position, 0, entry);
        }
        if (prependNew && newEntries.length > 0) {
            const added = new Set(newEntries);
            timelineEntries.sort((a, b) => {
                if (a.kind !== 'history' || b.kind !== 'history') return 0;
                return Number(a.item?.index ?? 0) - Number(b.item?.index ?? 0);
            });
        }
    }
    function appendHistoryEntry(parent, item, resultMap, consumed) {
        const messageNode = renderMessage(item, resultMap, consumed);
        if (item.index !== undefined && item.index !== null) {
            messageNode.dataset.historyIndex = String(item.index);
        }
        parent.appendChild(messageNode);
    }
    function firstLoadedGap() {
        const indexes = [...new Set(historyItems
            .map((item) => Number(item.index))
            .filter(Number.isInteger))].sort((a, b) => a - b);
        for (let position = 1; position < indexes.length; position += 1) {
            const start = indexes[position - 1] + 1;
            const end = indexes[position] - 1;
            if (end >= start) return { start, end };
        }
        return null;
    }
    async function loadMissingRange(start, end, trigger = null) {
        if (loadingEarlier || !Number.isInteger(start) || !Number.isInteger(end) || end < start) return;
        loadingEarlier = true;
        const missingCount = end - start + 1;
        const load = async () => {
            setStatus(`Loading ${missingCount} missing history ${missingCount === 1 ? 'entry' : 'entries'}...`, false, true);
            try {
                const result = await fetchHistory(`${start}-${end}`);
                const merged = new Map(historyItems.map((item) => [String(item.index), item]));
                result.items.forEach((item) => merged.set(String(item.index), item));
                historyItems = [...merged.values()].sort((a, b) => Number(a.index) - Number(b.index));
                const rangeFirst = result.firstIndex === null || result.firstIndex === undefined || result.firstIndex === ''
                    ? null : Number(result.firstIndex);
                const rangeLast = result.lastIndex === null || result.lastIndex === undefined || result.lastIndex === ''
                    ? null : Number(result.lastIndex);
                if (Number.isInteger(rangeFirst)) firstIndex = Number.isInteger(Number(firstIndex)) ? Math.min(Number(firstIndex), rangeFirst) : rangeFirst;
                if (Number.isInteger(rangeLast)) lastIndex = Number.isInteger(Number(lastIndex)) ? Math.max(Number(lastIndex), rangeLast) : rangeLast;
                reconcileTimeline(historyItems);
                render();
                updateHistoryControls();
                setStatus('');
            } catch (error) {
                setStatus(error.message || 'Unable to load missing history entries.', true);
            }
        };
        try {
            if (trigger && window.maiaUi?.runBusy) await window.maiaUi.runBusy(trigger, 'Loading entries...', load);
            else await load();
        } finally {
            loadingEarlier = false;
            turnCount.disabled = false;
        }
    }
    function renderNow() {
        if (activeFloatingState) {
            activeFloatingState.floatingActions.hidden = true;
            activeFloatingState.container.classList.remove('session-history-entry-actions-floating-visible');
            activeFloatingState = null;
        }
        floatingCandidates.clear();
        for (const container of actionContainers) {
            if (actionResizeObserver) actionResizeObserver.unobserve(container);
            const state = actionToolbarStates.get(container);
            if (state && actionVisibilityObserver) {
                actionVisibilityObserver.unobserve(container);
                actionVisibilityObserver.unobserve(state.bottomActions);
                if (state.sizeTarget) actionVisibilityObserver.unobserve(state.sizeTarget);
            }
            if (state && actionResizeObserver && state.sizeTarget) {
                actionResizeObserver.unobserve(state.sizeTarget);
            }
            floatingCandidates.delete(state);
            actionToolbarStates.delete(container);
        }
        actionContainers.clear();
        itemsNode.replaceChildren();
        const hasVisibleTimelineEntry = timelineEntries.some((entry) => {
            if (entry.kind === 'output') return Boolean(entry.node);
            if (entry.kind === 'optimistic-user') return entry.visible !== false;
            return entry.kind === 'history';
        });
        if (!hasVisibleTimelineEntry) {
            const empty = document.createElement('p');
            empty.className = 'session-history-empty';
            empty.textContent = 'No conversation history.';
            itemsNode.appendChild(empty);
        }

        const callIds = new Set();
        const results = new Map();
        for (const item of historyItems) {
            if (item.role === 'assistant') {
                for (const call of item.tool_calls || []) {
                    if (call?.id) callIds.add(call.id);
                }
            }
            if (item.role === 'tool' && item.tool_call_id) {
                const list = results.get(item.tool_call_id) || [];
                list.push(item);
                results.set(item.tool_call_id, list);
            }
        }

        const consumed = new Set();
        let previousHistoryIndex = null;

        for (const entry of timelineEntries) {
            if (entry.kind === 'output') {
                if (entry.node) itemsNode.appendChild(entry.node);
                continue;
            }
            if (entry.kind === 'optimistic-user') {
                if (entry.visible === false) continue;
                const user = document.createElement('article');
                user.className = 'session-history-message user session-history-optimistic-user';
                user.textContent = String(entry.item.content ?? '');
                itemsNode.appendChild(user);
                continue;
            }
            if (entry.kind !== 'history') continue;

            const item = entry.item;
            const itemIndex = Number(item.index);
            if (Number.isInteger(itemIndex)) {
                if (previousHistoryIndex !== null && itemIndex > previousHistoryIndex + 1) {
                    const gap = document.createElement('button');
                    gap.type = 'button';
                    gap.className = 'session-history-gap';
                    const missingCount = itemIndex - previousHistoryIndex - 1;
                    gap.textContent = `··· ${missingCount} ${missingCount === 1 ? 'entry' : 'entries'} not loaded ···`;
                    gap.title = `Load ${missingCount} missing entries.`;
                    gap.setAttribute('aria-label', gap.title);
                    const gapStart = previousHistoryIndex + 1;
                    const gapEnd = itemIndex - 1;
                    gap.addEventListener('click', () => {
                        void loadMissingRange(gapStart, gapEnd, gap);
                    });
                    itemsNode.appendChild(gap);
                }
                previousHistoryIndex = itemIndex;
            }
            if (item.role === 'reasoning' && (mode === 'hidden' || mode === 'collapsed')) continue;
            if (mode === 'hidden') {
                if (item.role === 'tool' && callIds.has(item.tool_call_id)) continue;
                if (item.role === 'assistant' && Array.isArray(item.tool_calls)) {
                    const calls = item.tool_calls.filter((call) => !results.has(call?.id));
                    const hasText = String(item.content ?? '').trim() !== '';
                    if (!hasText && calls.length === 0) continue;
                    const clone = { ...item, tool_calls: calls };
                    appendHistoryEntry(itemsNode, clone, results, consumed);
                    continue;
                }
            }
            if (item.role === 'tool' && mode !== 'timeline' && callIds.has(item.tool_call_id)) {
                if (consumed.has(item)) continue;
                if (mode === 'collapsed' || mode === 'groups') continue;
            }
            let clone = item;
            if (item.role === 'tool' && !callIds.has(item.tool_call_id)) {
                clone = { ...item, toolUnpairedReason: 'No matching call in the loaded history.' };
            }
            appendHistoryEntry(itemsNode, clone, results, consumed);
        }
        const n = Number(firstIndex);
        if (!timelineEntries.length || (Number.isInteger(n) && n <= 1)) {
            const start = document.createElement('div');
            start.className = 'session-start';
            start.textContent = 'Beginning of session';
            itemsNode.prepend(start);
        }
        if (selectedHistoryIndex !== null) {
            const selected = Array.from(itemsNode.querySelectorAll('[data-history-index]'))
                .find((node) => node.dataset.historyIndex === selectedHistoryIndex);
            if (selected) selected.classList.add('session-history-entry-selected');
        }
    }
    function updateResumeAvailability() {
        let lastUserPosition = -1;
        for (let index = 0; index < historyItems.length; index += 1) {
            if (historyItems[index].role === 'user') lastUserPosition = index;
        }

        let lastAssistant = null;
        if (lastUserPosition >= 0) {
            for (let index = lastUserPosition + 1; index < historyItems.length; index += 1) {
                if (historyItems[index].role === 'assistant') lastAssistant = historyItems[index];
            }
        }

        let available = false;
        if (lastUserPosition >= 0 && !lastAssistant) {
            available = true;
        } else if (lastAssistant) {
            let calls = [];
            if (Array.isArray(lastAssistant.tool_calls) && lastAssistant.tool_calls.length > 0) {
                calls = lastAssistant.tool_calls;
            } else if (Array.isArray(lastAssistant.backup?.tool_calls)) {
                calls = lastAssistant.backup.tool_calls;
            }
            available = calls.length > 0;
        }

        window.maiaSessionResumeAvailable = available;
        window.dispatchEvent(new CustomEvent('maia:resume-availability', {
            detail: { available }
        }));
    }

    function render(forceComposer = false, preserveScrollPosition = false) {
        updateResumeAvailability();
        if (selectionIsInHistory()) {
            pendingRender = true;
            return;
        }
        pendingRender = false;
        return preserveViewport(renderNow, forceComposer, preserveScrollPosition);
    }
    function itemsInLoadedRange() {
        const first = firstIndex === null || firstIndex === undefined || firstIndex === '' ? null : Number(firstIndex);
        const last = lastIndex === null || lastIndex === undefined || lastIndex === '' ? null : Number(lastIndex);
        if (!Number.isInteger(first) || !Number.isInteger(last)) return [];
        return historyItems.filter((item) => {
            const index = Number(item.index);
            return Number.isInteger(index) && index >= first && index <= last;
        });
    }
    function updateHistoryControls() {
        const index = Number(firstIndex);
        const earliestUser = itemsInLoadedRange().filter((item) => !isSticky(item) && item.role === 'user').map((item) => Number(item.user_index)).filter(Number.isInteger);
        const turnsBefore = earliestUser.length ? Math.max(0, Math.min(...earliestUser)) : 0;
        const hasEarlier = earliestUser.length ? turnsBefore > 0 : Number.isInteger(index) && index > 1;
        earlierButton.hidden = !hasEarlier; turnCountControl.hidden = !hasEarlier; allButton.hidden = !hasEarlier; remaining.hidden = !hasEarlier;
        if (hasEarlier) remaining.textContent = `Earlier history: ${Number.isInteger(index) ? Math.max(0, index - 1) : 0} messages · ${turnsBefore} turns`;
    }
    async function loadStickyHistory({ updateStatus = false } = {}) {
        const revision = historyMutationRevision;
        try {
            const result = await fetchHistory('', undefined, { stickyOnly: true });
            // A user may change flags while this secondary request is in flight.
            // Discard its stale snapshot rather than restoring an outdated flag.
            if (revision !== historyMutationRevision) return;
            const merged = new Map(historyItems.map((item) => [String(item.index), item]));
            result.items.forEach((item) => merged.set(String(item.index), item));
            historyItems = [...merged.values()].sort((a, b) => Number(a.index) - Number(b.index));
            reconcileTimeline(historyItems);
            render();
            updateHistoryControls();
            if (updateStatus) {
                setStatus('');
                dispatch('maia:history-operation-status', { busy:false });
            }
        } catch (error) {
            const message = error.message || 'Unable to load sticky history entries.';
            setStatus(message, true);
            if (updateStatus) {
                dispatch('maia:history-operation-status', { busy:false, message, error:true });
            }
        }
    }
    async function load(range = 'turn', { preserve = false, deferSticky = false } = {}) {
        setStatus('Loading conversation...', false, true);
        dispatch('maia:history-operation-status', { busy:true, message:'Loading conversation...', loading:true });
        try {
            const result = await fetchHistory(range, undefined, { includeSticky: !deferSticky });
            if (preserve) {
                const existing = new Map(historyItems.map((item) => [String(item.index), item]));
                result.items.forEach((item) => existing.set(String(item.index), item));
                historyItems = [...existing.values()].sort((a, b) => Number(a.index) - Number(b.index));
                firstIndex = result.firstIndex; lastIndex = result.lastIndex;
            } else { historyItems = result.items; firstIndex = result.firstIndex; lastIndex = result.lastIndex; }
            reconcileTimeline(historyItems);
            render();
            updateHistoryControls();
            if (deferSticky) {
                setStatus('Loading conversation...', false, true);
                dispatch('maia:history-operation-status', { busy:true, message:'Loading conversation...', loading:true });
                void loadStickyHistory({ updateStatus: true });
            } else {
                setStatus('');
                dispatch('maia:history-operation-status', { busy:false });
            }
            return result;
        } catch (error) {
            const message = error.message || 'Unable to load conversation history.';
            setStatus(message, true);
            dispatch('maia:history-operation-status', { busy:false, message, error:true });
            return null;
        }
    }
    function countToLoad() {
        const clean = turnCount.value.replace(/[^0-9]/g, '').slice(0, 3);
        const count = Math.max(1, Number.parseInt(clean || '1', 10)); turnCount.value = String(count); return count;
    }
    turnCount.addEventListener('input', () => { turnCount.value = turnCount.value.replace(/[^0-9]/g, '').slice(0, 3); });
    async function loadEarlier() {
        if (loadingEarlier) return;
        const gap = firstLoadedGap();
        if (gap) {
            await loadMissingRange(gap.start, gap.end, earlierButton);
            return;
        }
        const userIndexes = itemsInLoadedRange().filter((item) => !isSticky(item) && item.role === 'user').map((item) => Number(item.user_index)).filter(Number.isInteger);
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
                firstIndex = result.firstIndex ?? firstIndex;
                reconcileTimeline(historyItems, false, true);
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
            try { const result = await fetchHistory('all'); historyItems = result.items; firstIndex = result.firstIndex; lastIndex = result.lastIndex; reconcileTimeline(historyItems, false, true); render(); updateHistoryControls(); setStatus(''); }
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
            // After a send, refresh from the first currently loaded message so
            // the existing visible turns stay loaded along with the new turn.
            let result = await fetchHistory(completedSend
                ? (Number.isInteger(Number(firstIndex)) ? `${Number(firstIndex)}-` : 'turn')
                : range);
            if (completedSend) {
                if (completedSend.resume) {
                    historyItems = result.items;
                    firstIndex = result.firstIndex;
                    lastIndex = result.lastIndex;
                    reconcileTimeline(historyItems);
                    if (completedSend.outputNode instanceof HTMLDetailsElement && !completedSend.failed &&
                        completedSend.outputNode.dataset.leadingError !== 'true') {
                        completedSend.outputNode.open = false;
                    }
                    if (activeSend === completedSend) activeSend = null;
                    render();
                    updateHistoryControls();
                    return { ok: true, completed: completedSend.failed !== true, pending: false };
                }
                if (Number(result.rangeItemCount ?? result.items.length) === 0) {
                    completedSend.showUser = false;
                    if (completedSend.userTimelineEntry && completedSend.userTimelineEntry.kind === 'optimistic-user') {
                        completedSend.userTimelineEntry.visible = false;
                    }
                    completedSend.failedSettled = completedSend.failed === true;
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
                const previousFirstItem = historyItems.find((item) => Number(item.index) === Number(firstIndex)) ??
                    historyItems.find((item) => !isSticky(item)) ?? null;
                const anchorWasPreserved = !previousFirstItem || result.items.some((item) =>
                    item.role === previousFirstItem.role &&
                    ((previousFirstItem.id !== undefined && previousFirstItem.id !== null &&
                        String(item.id ?? '') === String(previousFirstItem.id)) ||
                     ((previousFirstItem.id === undefined || previousFirstItem.id === null) &&
                        String(item.timestamp ?? '') === String(previousFirstItem.timestamp ?? '') &&
                        Number(item.index) === Number(previousFirstItem.index)))
                );
                if (!anchorWasPreserved) {
                    // Earlier history changed and shifted indexes while the send
                    // was running. Reload authoritatively, then retain the same
                    // number of previously visible turns plus the new turn.
                    const allHistory = await fetchHistory('all');
                    const visibleItems = allHistory.items.filter((item) => !isSticky(item));
                    const visibleTurns = historyItems.filter((item) => !isSticky(item) && item.role === 'user').length + 1;
                    const userPositions = [];
                    visibleItems.forEach((item, position) => {
                        if (item.role === 'user') userPositions.push(position);
                    });
                    const firstVisiblePosition = userPositions.length > visibleTurns
                        ? userPositions[userPositions.length - visibleTurns]
                        : 0;
                    const selectedItems = visibleItems.slice(firstVisiblePosition);
                    const selectedByIndex = new Map([...selectedItems, ...allHistory.items.filter(isSticky)]
                        .map((item) => [String(item.index), item]));
                    result = {
                        ...allHistory,
                        firstIndex: selectedItems[0]?.index ?? allHistory.firstIndex,
                        items: [...selectedByIndex.values()].sort((a, b) => Number(a.index) - Number(b.index))
                    };
                }
                historyItems = result.items;
                firstIndex = result.firstIndex ?? historyItems.find((item) => !isSticky(item))?.index ?? null;
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
                    completedSend.showUser = false;
                    if (completedSend.userTimelineEntry && completedSend.userTimelineEntry.kind === 'optimistic-user') {
                        completedSend.userTimelineEntry.visible = false;
                    }
                    reconcileTimeline(historyItems);
                    completedSend.failedSettled = completedSend.failed === true;
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
                bindOptimisticUser(completedSend, sentUser);
                reconcileTimeline(historyItems);
                const sentUserIndex = Number(sentUser.index);
                sendResponseCompleted = result.items.some((item) => {
                    const itemIndex = Number(item.index);
                    return item.role === 'assistant' && Number.isInteger(itemIndex) &&
                        itemIndex > sentUserIndex &&
                        (String(item.content ?? '').trim() !== '' ||
                            (Array.isArray(item.tool_calls) && item.tool_calls.length > 0));
                });
                if (completedSend.outputNode instanceof HTMLDetailsElement) {
                    const selection = document.getSelection();
                    const selectionWithinOutput = selection && !selection.isCollapsed &&
                        (completedSend.outputNode.contains(selection.anchorNode) ||
                            completedSend.outputNode.contains(selection.focusNode));
                    // Keep selected raw output expanded. Explicitly reopen it if
                    // another update collapsed it before this history refresh.
                    if (selectionWithinOutput || completedSend.outputNode.dataset.leadingError === 'true') {
                        completedSend.outputNode.open = true;
                    } else {
                        completedSend.outputNode.open = false;
                    }
                }
                sendResponsePending = completedSend.failed === true && !sendResponseCompleted;
                if (sendResponsePending) {
                    const failedIndex = Number(sentUser.index);
                    try {
                        if (Number.isInteger(failedIndex)) {
                            await window.maiaApi.request('/api/history/action', {
                                method: 'POST',
                                headers: { 'Content-Type': 'application/json' },
                                body: JSON.stringify({ action: 'delete', index: failedIndex })
                            });
                        }
                    } catch (error) {
                        console.error('Unable to remove the failed user message from history:', error);
                    }
                    completedSend.showUser = false;
                    if (completedSend.userTimelineEntry && completedSend.userTimelineEntry.kind === 'optimistic-user') {
                        completedSend.userTimelineEntry.visible = false;
                    }
                    completedSend.failedSettled = true;
                    historyItems = historyItems
                        .filter((item) => !(item.role === 'user' && Number(item.index) === failedIndex &&
                            (!sentUser.id || String(item.id ?? '') === String(sentUser.id))))
                        .map((item) => {
                            const updated = { ...item };
                            const index = Number(updated.index);
                            if (Number.isInteger(index) && index > failedIndex) updated.index = index - 1;
                            if (updated.role === 'user' && Number(updated.user_index) > Number(sentUser.user_index)) {
                                updated.user_index = Number(updated.user_index) - 1;
                            }
                            return updated;
                        });
                    firstIndex = historyItems.find((item) => !isSticky(item))?.index ?? null;
                    lastIndex = [...historyItems].reverse().find((item) => !isSticky(item))?.index ?? null;
                    reconcileTimeline(historyItems, true);
                    sendResponsePending = false;
                }
                if (!sendResponsePending && activeSend === completedSend) activeSend = null;
                render();
                updateHistoryControls();
            } else {
                historyItems = result.items;
                firstIndex = result.firstIndex;
                lastIndex = result.lastIndex;
                reconcileTimeline(historyItems);
                render();
                updateHistoryControls();
            }
            setStatus('');
            return { ok: true, completed: sendResponseCompleted, pending: sendResponsePending };
        } catch (error) {
            if (completedSend) {
                completedSend.showUser = false;
                if (completedSend.userTimelineEntry && completedSend.userTimelineEntry.kind === 'optimistic-user') {
                    completedSend.userTimelineEntry.visible = false;
                }
                completedSend.failedSettled = completedSend.failed === true;
                render();
            }
            const message = error.message || 'Unable to refresh conversation history.';
            setStatus(message, true);
            return { ok: false, error: message };
        }
    }
    async function wholeHistoryAction(actionName, message) {
        const title = actionName === 'clear' ? 'Delete history'
            : actionName === 'compact' ? 'Compact history'
            : actionName === 'prune-tools' ? 'Prune tools'
            : actionName === 'hide-all' ? 'Hide history' : 'Hide last turn';
        if (!await window.maiaUi.confirmAction({
            title,
            message,
            actionLabel: title,
            actionType: actionName === 'clear' ? 'action-warning' : 'action-normal'
        })) return;
        historyMutationRevision += 1;
        await withHistoryMutation(async () => {
            let progressMessage;
            switch (actionName) {
                case 'compact':
                    progressMessage = 'Compacting history...';
                    break;
                case 'prune-tools':
                    progressMessage = 'Pruning tools...';
                    break;
                case 'clear':
                    progressMessage = 'Deleting history...';
                    break;
                default:
                    progressMessage = 'Updating history...';
            }
            dispatch('maia:history-operation-status', { busy:true, message:progressMessage, loading:true });
            try {
                await window.maiaApi.request('/api/history/action', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({ action:actionName }) });
                await refreshHistoryAfterMutation();
                dispatch('maia:history-operation-status', { busy:false });
            } catch (error) {
                dispatch('maia:history-operation-status', {
                    busy:false,
                    message:error.message || 'Unable to update history.',
                    error:true
                });
            }
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
        if (!await window.maiaUi.confirmAction({
            title: 'Delete session',
            message: `Permanently delete session “${session}”? Its history and other session data will be removed and cannot be recovered.`,
            actionLabel: 'Delete',
            actionType: 'action-warning'
        })) return;
        setStatus('Deleting session...', false, true);
        const controller = new AbortController();
        let timedOut = false;
        const timeoutId = window.setTimeout(() => {
            timedOut = true;
            controller.abort();
        }, 30_000);
        try {
            await window.maiaApi.request('/api/session/delete', {
                method:'POST', headers:{'Content-Type':'text/plain; charset=utf-8'}, body:session,
                signal:controller.signal
            });
            window.location.assign(`${basePath}/`);
        } catch (error) {
            setStatus(timedOut
                ? 'Session deletion timed out. It may still be in progress; refresh the session list to check.'
                : (error.message || 'Unable to delete session.'), true);
        } finally {
            window.clearTimeout(timeoutId);
        }
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
            {icon:'⚒↕',label:'Prune tools',danger:false,run:() => wholeHistoryAction('prune-tools','Prune tool output throughout the history? Tool output will be reduced to placeholders where that saves space, with original content retained for restoration.')},
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
            resume: event.detail?.resume === true,
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
            showUser: event.detail?.resume !== true,
            completed: false,
            userTimelineEntry: null
        };
        if (activeSend.showUser) {
            activeSend.userTimelineEntry = {
                kind: 'optimistic-user',
                item: { role: 'user', content: activeSend.message },
                visible: true,
                bound: false
            };
            timelineEntries.push(activeSend.userTimelineEntry);
        }
        if (activeSend.outputNode) {
            timelineEntries.push({ kind: 'output', node: activeSend.outputNode });
        }
        setStatus('');
        render(true);
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
            // The submitted text remains in the composer as the editable draft;
            // do not keep a failed send's optimistic user entry in history.
            activeSend.showUser = false;
            if (activeSend.userTimelineEntry && activeSend.userTimelineEntry.kind === 'optimistic-user') {
                activeSend.userTimelineEntry.visible = false;
            }
            render();
        }
        setStatus(error, true);
    });
    window.addEventListener('maia:send-failure-settled', () => {
        if (activeSend?.failed) activeSend.failedSettled = true;
    });
    window.addEventListener('maia:history-refresh', (event) => {
        void refresh().then((result) => event.detail?.done?.(result)).catch((error) =>
            event.detail?.done?.({ ok: false, error: error.message || 'Unable to refresh conversation history.' })
        );
    });
    turnCount.addEventListener('keydown', (event) => { if (event.key === 'Enter') { event.preventDefault(); loadEarlier(); } });
    load('turn', { deferSticky: true });
})();
