/* Tools panel behavior. */
(() => {
    'use strict';

    const byId = (id) => document.getElementById(id);
    function currentContextScope() {
        const context = document.body?.dataset || {};
        if (context.maiaProfile) return 'profile';
        if (context.maiaSession) return 'session';
        if (context.maiaWorkspace) return 'workspace';
        if (context.maiaHome) return 'home';
        return 'session';
    }

    const api = (path, ...args) => {
        const scopedPath = typeof path === 'string' && path.startsWith('/api/tool/')
            ? path.replace(/([?&])scope=[^&]*/, `$1scope=${encodeURIComponent(currentContextScope())}`)
            : path;
        return window.maiaApi.request(scopedPath, ...args);
    };
    const jsonOptions = (body) => ({
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
    });
    let loaded = false;
    const selectedPatterns = new Set();
    const pendingListOperations = new Set();
    const completedListOperations = [];
    let finalizingListOperations = false;

    function syncRemoveSelected() {
        byId('tool-remove-selected').hidden = selectedPatterns.size === 0;
    }

    function beginListOperation(type, label, rows = [], count = 1) {
        const operation = { type, label, count, error: '', success: '' };
        pendingListOperations.add(operation);
        if (type === 'edit') {
            selectedPatterns.delete(label);
            syncRemoveSelected();
        }
        for (const row of rows) {
            row.dataset.listOperationPending = 'true';
            row.querySelectorAll('input, button').forEach((control) => { control.disabled = true; });
        }
        syncPendingStatus();
        return operation;
    }

    function syncPendingStatus() {
        const operations = [...pendingListOperations];
        const removing = operations.filter((operation) => operation.type === 'remove');
        const editing = operations.filter((operation) => operation.type === 'edit');
        const removeCount = removing.reduce((total, operation) => total + operation.count, 0);
        const editCount = editing.reduce((total, operation) => total + operation.count, 0);
        const availableCount = operations.filter((operation) => operation.type === 'available')
            .reduce((total, operation) => total + operation.count, 0);
        if (removeCount > 1) setLoadingStatus(`Removing ${removeCount} entries...`);
        else if (removeCount === 1) setLoadingStatus(`Removing ${removing[0].label}.`);
        else if (editCount === 1) setLoadingStatus(`Updating ${editing[0].label}...`);
        else if (editCount > 1) setLoadingStatus(`Updating ${editCount} entries...`);
        else if (availableCount === 1) setLoadingStatus(`Updating ${operations.find((operation) => operation.type === 'available').label}...`);
        else if (availableCount > 1) setLoadingStatus(`Updating ${availableCount} entries...`);
    }

    async function finishListOperation(operation, error = null, success = '') {
        operation.error = error ? `${operation.label}: ${error.message || error}` : '';
        operation.success = success;
        pendingListOperations.delete(operation);
        completedListOperations.push(operation);
        if (pendingListOperations.size > 0) {
            syncPendingStatus();
            return;
        }
        finalizingListOperations = true;
        loaded = false;
        const refreshed = await loadTools();
        const results = completedListOperations.splice(0);
        finalizingListOperations = false;
        const errors = results.filter((result) => result.error).map((result) => result.error);
        if (errors.length) setStatus(`Unable to complete: ${errors.join('; ')}`, true);
        else if (refreshed) setStatus(results.at(-1)?.success || '');
    }

    function setStatus(message, isError = false) {
        window.maiaUi.setStatus('tools-status', message, { error: isError });
    }

    function setLoadingStatus(message) {
        window.maiaUi.setLoadingStatus('tools-status', message);
    }

    function makeButton(label, title, handler) {
        const button = document.createElement('button');
        button.type = 'button';
        button.textContent = label;
        button.title = title;
        button.setAttribute('aria-label', title);
        button.className = 'small-action';
        button.addEventListener('click', () => {
            Promise.resolve(handler()).catch((error) => setStatus(error.message, true));
        });
        return button;
    }

    function renderPatterns(list, patterns, onRemove, onChange) {
        list.replaceChildren();
        for (const pattern of patterns) {
            const item = document.createElement('li');
            const checkbox = document.createElement('input');
            checkbox.type = 'checkbox';
            checkbox.className = 'item-selector';
            checkbox.checked = selectedPatterns.has(pattern);
            checkbox.setAttribute('aria-label', `Select ${pattern}`);
            checkbox.addEventListener('change', () => {
                if (checkbox.disabled) return;
                if (checkbox.checked) selectedPatterns.add(pattern);
                else selectedPatterns.delete(pattern);
                syncRemoveSelected();
            });
            const text = document.createElement('span');
            text.className = 'item-label';
            text.textContent = pattern;
            let editInput = null;
            const editButton = makeButton('\u270E', `Edit ${pattern}`, () => {
                if (editInput) {
                    editInput.remove();
                    editInput = null;
                    item.classList.remove('is-editing');
                    checkbox.hidden = false;
                    text.hidden = false;
                    editButton.textContent = '\u270E';
                    editButton.title = `Edit ${pattern}`;
                    editButton.setAttribute('aria-label', `Edit ${pattern}`);
                    removeButton.textContent = '\u00D7';
                    removeButton.title = `Remove ${pattern}`;
                    removeButton.setAttribute('aria-label', `Remove ${pattern}`);
                    return;
                }
                selectedPatterns.delete(pattern);
                checkbox.checked = false;
                checkbox.hidden = true;
                syncRemoveSelected();
                editInput = document.createElement('input');
                editInput.type = 'text';
                editInput.className = 'item-edit-input';
                editInput.value = pattern;
                editInput.setAttribute('aria-label', `Edit ${pattern}`);
                editInput.addEventListener('keydown', (event) => {
                    if (event.key === 'Enter') { event.preventDefault(); removeButton.click(); }
                    if (event.key === 'Escape') { event.preventDefault(); editButton.click(); }
                });
                text.hidden = true;
                item.insertBefore(editInput, text);
                item.classList.add('is-editing');
                editButton.textContent = '\u21B6';
                editButton.title = `Cancel editing ${pattern}`;
                editButton.setAttribute('aria-label', `Cancel editing ${pattern}`);
                removeButton.textContent = '\u2713';
                removeButton.title = `Save ${pattern}`;
                removeButton.setAttribute('aria-label', `Save ${pattern}`);
                editInput.focus();
                editInput.select();
            });
            const removeButton = makeButton('\u00D7', `Remove ${pattern}`, () => {
                if (editInput) {
                    const replacement = editInput.value.trim();
                    if (!replacement) { editInput.focus(); return; }
                    if (replacement === pattern) { editButton.click(); return; }
                    return onChange(pattern, replacement, item);
                }
                return onRemove(pattern, item);
            });
            item.append(checkbox, text, editButton, removeButton);
            list.appendChild(item);
        }
        syncRemoveSelected();
    }

    async function requestTool(action, pattern = '', replacement = '') {
        if (action === 'change') {
            return api('/api/tool/context?scope=home', jsonOptions({ action, pattern, replacement }));
        }
        const options = pattern
            ? { method: 'POST', headers: { 'Content-Type': 'text/plain; charset=utf-8' }, body: pattern }
            : { method: 'POST' };
        return api(`/api/tool/${action}?scope=home`, options);
    }

    async function updateTool(action, pattern = '', replacement = '') {
        try {
            await requestTool(action, pattern, replacement);
            loaded = false;
            await loadTools();
        } catch (error) {
            loaded = false;
            await loadTools();
            setStatus(error.message, true);
        }
    }

    async function removeTool(pattern, item) {
        item.remove();
        selectedPatterns.delete(pattern);
        syncRemoveSelected();
        const operation = beginListOperation('remove', pattern);
        try {
            await requestTool('disable', pattern);
            await finishListOperation(operation, null, `Removed ${pattern}.`);
        } catch (error) { await finishListOperation(operation, error); }
    }

    async function editTool(pattern, replacement, item) {
        const operation = beginListOperation('edit', pattern, [item]);
        try {
            await requestTool('change', pattern, replacement.trim());
            await finishListOperation(operation, null, `Updated ${pattern}.`);
        } catch (error) { await finishListOperation(operation, error); }
    }

    async function removeSelectedTools() {
        const patterns = [...selectedPatterns];
        const rows = [...byId('tool-pattern-list').children];
        rows.filter((row) => selectedPatterns.has(row.querySelector('.item-label')?.textContent))
            .forEach((row) => row.remove());
        selectedPatterns.clear();
        syncRemoveSelected();
        const operation = beginListOperation('remove', `${patterns.length} patterns`, [], patterns.length);
        const failures = [];
        for (const pattern of patterns) {
            try { await requestTool('disable', pattern); }
            catch (error) { failures.push(`${pattern}: ${error.message}`); }
        }
        await finishListOperation(operation, failures.length ? new Error(failures.join('; ')) : null,
            `Removed ${patterns.length} pattern${patterns.length === 1 ? '' : 's'}.`);
    }

    async function addTool(pattern, availableRow = null) {
        const input = byId('tool-pattern');
        const value = (pattern || input.value).trim();
        if (!value) return;
        if (availableRow) {
            const operation = beginListOperation('available', value, [availableRow]);
            try {
                await requestTool('append', value);
                await finishListOperation(operation, null, `Allowed ${value}.`);
            } catch (error) { await finishListOperation(operation, error); }
        } else {
            await updateTool('append', value);
        }
        if (input) input.value = '';
    }

    async function loadTools() {
        if (pendingListOperations.size > 0 && !finalizingListOperations) return false;
        byId('tool-delete').hidden = true;
        setLoadingStatus('Loading tools…');
        try {
            const result = await api('/api/tool/context?scope=home');
            const scopeLabel = byId('tools-scope');
            scopeLabel.textContent = `Tool scope '${result.scope || 'home'}'`;
            const displayedScope = scopeLabel.textContent.match(/^Tool scope '(.+)'$/)?.[1] || '';
            byId('tool-delete').hidden = displayedScope !== currentContextScope();
            renderPatterns(byId('tool-pattern-list'), result.patterns || [], removeTool, editTool);
            const list = byId('available-tools-list');
            const heading = list.querySelector('.available-resource-heading');
            list.replaceChildren();
            if (heading) list.appendChild(heading);
            for (const tool of result.tools || []) {
                const item = document.createElement('li');
                const label = document.createElement('span');
                label.textContent = tool.description ? `${tool.name} — ${tool.description}` : tool.name;
                const effects = document.createElement('span');
                effects.textContent = (tool.effects || []).join(', ') || '—';
                const pattern = tool.effects?.length ? `${tool.name}:${tool.effects.join('+')}` : tool.name;
                const allowed = tool.allowed || (result.patterns || []).includes(pattern) || (result.patterns || []).includes(tool.name);
                const state = document.createElement('span');
                state.className = 'available-resource-state';
                state.append(allowed
                    ? Object.assign(document.createElement('span'), { textContent: 'Yes' })
                    : makeButton('No', `Allow ${tool.name}`, () => addTool(pattern, item)));
                const missingExecutables = Array.isArray(tool.execDependenciesMissing)
                    ? tool.execDependenciesMissing.filter((executable) => typeof executable === 'string' && executable)
                    : [];
                if (missingExecutables.length) {
                    const warning = document.createElement('details');
                    warning.className = 'tool-dependency-warning';
                    const summary = document.createElement('summary');
                    summary.textContent = '\u26A0';
                    summary.title = `Unavailable: missing ${missingExecutables.join(', ')}`;
                    summary.setAttribute('aria-label', `Unavailable: missing executable${missingExecutables.length === 1 ? '' : 's'} ${missingExecutables.join(', ')}`);
                    const explanation = document.createElement('span');
                    explanation.textContent = `Missing executable${missingExecutables.length === 1 ? '' : 's'}: ${missingExecutables.join(', ')}`;
                    warning.append(summary, explanation);
                    state.appendChild(warning);
                }
                item.append(label, effects, state);
                list.appendChild(item);
            }
            if (list.children.length === (heading ? 1 : 0)) {
                const empty = document.createElement('li');
                empty.textContent = 'No available tools.';
                list.appendChild(empty);
            }
            setStatus(result.patterns?.length ? '' : 'No tool patterns configured.');
            loaded = true;
            return true;
        } catch (error) { setStatus(error.message, true); return false; }
    }

    document.addEventListener('maia:panel-open', (event) => {
        if (event.detail?.id === 'tools' && !loaded) loadTools();
    });
    window.maiaUi.bindBusyClick(byId('tool-remove-selected'), removeSelectedTools, {
        busyText: 'Removing selected tool patterns…',
        onError: (error) => setStatus(error.message, true)
    });
    window.maiaUi.bindBusyClick(byId('tool-pattern-add'), () => addTool(), {
        busyText: 'Adding tool pattern\u2026',
        onError: (error) => setStatus(error.message, true)
    });
    byId('tool-pattern')?.addEventListener('keydown', (event) => {
        if (event.key === 'Enter') { event.preventDefault(); addTool(); }
    });
    window.maiaUi.bindBusyClick(byId('tool-clear'), () => updateTool('clear'), {
        busyText: 'Clearing tool patterns\u2026',
        onError: (error) => setStatus(error.message, true)
    });
    window.maiaUi.bindBusyClick(byId('tool-delete'), () => updateTool('delete'), {
        busyText: 'Deleting tool patterns\u2026',
        onError: (error) => setStatus(error.message, true)
    });
    window.maiaUi.bindBusyClick(byId('tools-refresh'), async () => {
        await api('/api/tool/context?scope=home', jsonOptions({ action: 'refresh', scope: 'home' }));
        loaded = false;
        await loadTools();
    }, {
        busyText: 'Refreshing tools\u2026',
        onError: (error) => setStatus(error.message, true)
    });
})();
