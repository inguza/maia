/* Approvals panel behavior. */
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

    let currentApprovalType = 'file';
    const approvalTypes = [
        { name: 'file', label: 'File', tab: 'approval-file-tab' },
        { name: 'exec', label: 'Exec', tab: 'approval-exec-tab' },
        { name: 'exec-def', label: 'Execdef', tab: 'approval-exec-def-tab' }
    ];
    const api = (path, ...args) => {
        if (typeof path === 'string' && path.startsWith('/api/approval/')) {
            const url = new URL(path, window.location.origin);
            url.searchParams.set('scope', currentContextScope());
            url.searchParams.set('type', currentApprovalType);
            path = `${url.pathname}${url.search}`;
        }
        return window.maiaApi.request(path, ...args);
    };
    let loaded = false;
    let loadGeneration = 0;
    const selectedRules = new Set();
    const pendingListOperations = new Set();
    const completedListOperations = [];

    function syncRemoveSelected() {
        byId('approval-remove-selected').hidden = selectedRules.size === 0;
    }

    function setStatus(message, isError = false) {
        window.maiaUi.setStatus('approvals-status', message, { error: isError });
    }

    function setLoadingStatus(message) {
        window.maiaUi.setLoadingStatus('approvals-status', message);
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

    function beginListOperation(type, label, rows = [], count = 1) {
        const operation = { type, label, count, error: '', success: '' };
        pendingListOperations.add(operation);
        if (type === 'edit') {
            selectedRules.delete(label);
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
        if (removeCount > 1) setLoadingStatus(`Removing ${removeCount} entries...`);
        else if (removeCount === 1) setLoadingStatus(`Removing ${removing[0].label}.`);
        else if (editCount === 1) setLoadingStatus(`Updating ${editing[0].label}...`);
        else if (editCount > 1) setLoadingStatus(`Updating ${editCount} entries...`);
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
        loaded = false;
        const refreshed = await loadApprovals();
        const results = completedListOperations.splice(0);
        const errors = results.filter((result) => result.error).map((result) => result.error);
        if (errors.length) setStatus(`Unable to complete: ${errors.join('; ')}`, true);
        else if (refreshed) setStatus(results.at(-1)?.success || '');
    }

    function renderRules(rules) {
        const list = byId('approval-rule-list');
        list.replaceChildren();
        for (const rule of rules) {
            const item = document.createElement('li');
            const checkbox = document.createElement('input');
            checkbox.type = 'checkbox';
            checkbox.className = 'item-selector';
            checkbox.checked = selectedRules.has(rule);
            checkbox.setAttribute('aria-label', `Select ${rule}`);
            checkbox.addEventListener('change', () => {
                if (checkbox.disabled) return;
                if (checkbox.checked) selectedRules.add(rule);
                else selectedRules.delete(rule);
                syncRemoveSelected();
            });
            const text = document.createElement('span');
            text.className = 'item-label';
            text.textContent = rule;
            let editInput = null;
            let editButton;
            let removeButton;
            editButton = makeButton('\u270E', `Edit ${rule}`, () => {
                if (editInput) {
                    editInput.remove(); editInput = null;
                    item.classList.remove('is-editing');
                    checkbox.hidden = false; text.hidden = false;
                    editButton.textContent = '\u270E';
                    editButton.title = `Edit ${rule}`;
                    editButton.setAttribute('aria-label', `Edit ${rule}`);
                    removeButton.textContent = '\u00D7';
                    removeButton.title = `Remove ${rule}`;
                    removeButton.setAttribute('aria-label', `Remove ${rule}`);
                    return;
                }
                selectedRules.delete(rule);
                checkbox.checked = false; checkbox.hidden = true; syncRemoveSelected();
                editInput = document.createElement('input');
                editInput.type = 'text'; editInput.className = 'item-edit-input'; editInput.value = rule;
                editInput.setAttribute('aria-label', `Edit ${rule}`);
                editInput.addEventListener('keydown', (event) => {
                    if (event.key === 'Enter') { event.preventDefault(); removeButton.click(); }
                    if (event.key === 'Escape') { event.preventDefault(); editButton.click(); }
                });
                text.hidden = true; item.insertBefore(editInput, text); item.classList.add('is-editing');
                editButton.textContent = '\u21B6';
                editButton.title = `Cancel editing ${rule}`;
                editButton.setAttribute('aria-label', `Cancel editing ${rule}`);
                removeButton.textContent = '\u2713';
                removeButton.title = `Save ${rule}`;
                removeButton.setAttribute('aria-label', `Save ${rule}`);
                editInput.focus(); editInput.select();
            });
            removeButton = makeButton('\u00D7', `Remove ${rule}`, () => {
                if (editInput) {
                    const replacement = editInput.value.trim();
                    if (!replacement) { editInput.focus(); return; }
                    if (replacement === rule) { editButton.click(); return; }
                    return editRule(rule, replacement, item);
                }
                return removeRule(rule, item);
            });
            item.append(checkbox, text, editButton, removeButton);
            list.appendChild(item);
        }
        syncRemoveSelected();
    }

    async function updateApproval(action, rule = '', replacement = '') {
        const options = action === 'change'
            ? { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ rule, replacement }) }
            : rule
                ? { method: 'POST', headers: { 'Content-Type': 'text/plain; charset=utf-8' }, body: rule }
                : { method: 'POST' };
        try {
            await api(`/api/approval/${action === 'change' ? 'change' : action}?scope=home`, options);
            loaded = false;
            await loadApprovals();
        } catch (error) {
            loaded = false;
            await loadApprovals();
            setStatus(error.message, true);
        }
    }

    async function editRule(rule, replacement, item) {
        const operation = beginListOperation('edit', rule, [item]);
        try {
            await api('/api/approval/change?scope=home', {
                method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ rule, replacement: replacement.trim() })
            });
            await finishListOperation(operation, null, `Updated ${rule}.`);
        } catch (error) { await finishListOperation(operation, error); }
    }

    async function removeRule(rule, item) {
        item.remove();
        selectedRules.delete(rule);
        syncRemoveSelected();
        const operation = beginListOperation('remove', rule);
        try {
            await api('/api/approval/disable?scope=home', { method: 'POST', headers: { 'Content-Type': 'text/plain; charset=utf-8' }, body: rule });
            await finishListOperation(operation, null, `Removed ${rule}.`);
        } catch (error) { await finishListOperation(operation, error); }
    }

    async function removeSelectedRules() {
        const rules = [...selectedRules];
        if (!rules.length) return;
        [...byId('approval-rule-list').children]
            .filter((row) => selectedRules.has(row.querySelector('.item-label')?.textContent))
            .forEach((row) => row.remove());
        selectedRules.clear();
        syncRemoveSelected();
        const operation = beginListOperation('remove', `${rules.length} rules`, [], rules.length);
        for (const rule of rules) {
            try {
                await api('/api/approval/disable?scope=home', { method: 'POST', headers: { 'Content-Type': 'text/plain; charset=utf-8' }, body: rule });
            } catch (error) {
                operation.error = operation.error ? `${operation.error}; ${rule}: ${error.message}` : `${rule}: ${error.message}`;
            }
        }
        const error = operation.error ? new Error(operation.error) : null;
        await finishListOperation(operation, error, `Removed ${rules.length} rule${rules.length === 1 ? '' : 's'}.`);
    }

    async function addRule() {
        const input = byId('approval-rule');
        const rule = input.value.trim();
        if (!rule) return;
        await updateApproval('append', rule);
        input.value = '';
    }

    async function loadApprovals() {
        if (pendingListOperations.size > 0) return false;
        const requestType = currentApprovalType;
        const generation = ++loadGeneration;
        setLoadingStatus('Loading approvals…');
        try {
            const result = await api('/api/approval/context?scope=home');
            if (generation !== loadGeneration || requestType !== currentApprovalType) return false;
            const effectiveScope = result.scope || 'default';
            const pageScope = result.targetScope || currentContextScope();
            const typeLabel = approvalTypes.find((type) => type.name === currentApprovalType)?.label || 'File';
            byId('approvals-scope').textContent = `${typeLabel} approval scope '${effectiveScope}'`;
            byId('approval-delete').hidden = effectiveScope !== pageScope;
            const rules = Array.isArray(result.rules) ? result.rules : [];
            renderRules(rules);
            setStatus(rules.length > 0 ? '' : 'No approval rules configured.');
            loaded = true;
            return true;
        } catch (error) {
            if (generation !== loadGeneration || requestType !== currentApprovalType) return false;
            setStatus(error.message || 'Unable to load approval rules.', true);
            return false;
        }
    }
    const approvalTabs = approvalTypes.map((type) => ({ ...type, button: byId(type.tab) }));
    function selectApprovalType(typeName, focus = false) {
        currentApprovalType = typeName;
        const active = approvalTabs.find((type) => type.name === typeName);
        for (const type of approvalTabs) {
            const selected = type.name === typeName;
            type.button.setAttribute('aria-selected', String(selected));
            type.button.tabIndex = selected ? 0 : -1;
        }
        byId('approval-content').setAttribute('aria-labelledby', active.tab);
        const input = byId('approval-rule');
        if (typeName === 'file') input.placeholder = 'Rule, e.g. logs/*:append';
        else if (typeName === 'exec') input.placeholder = 'Execution rule, e.g. grep ...:exec';
        else input.placeholder = 'Execution definition, e.g. ...:define util-grep';
        selectedRules.clear();
        loaded = false;
        syncRemoveSelected();
        if (focus) active.button.focus();
        void loadApprovals();
    }
    for (const [index, type] of approvalTabs.entries()) {
        type.button.addEventListener('click', () => {
            if (currentApprovalType !== type.name) selectApprovalType(type.name);
        });
        type.button.addEventListener('keydown', (event) => {
            let next = null;
            if (event.key === 'ArrowRight' || event.key === 'ArrowDown') next = (index + 1) % approvalTabs.length;
            if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') next = (index + approvalTabs.length - 1) % approvalTabs.length;
            if (event.key === 'Home') next = 0;
            if (event.key === 'End') next = approvalTabs.length - 1;
            if (next !== null) {
                event.preventDefault();
                selectApprovalType(approvalTabs[next].name, true);
            }
        });
    }
    document.addEventListener('maia:panel-open', (event) => {
        if (event.detail?.id === 'approvals' && !loaded) void loadApprovals();
    });
    window.maiaUi.bindBusyClick(byId('approval-remove-selected'), removeSelectedRules, {
        busyText: 'Removing selected approval rules…',
        onError: (error) => setStatus(error.message, true)
    });
    window.maiaUi.bindBusyClick(byId('approval-rule-add'), addRule, {
        busyText: 'Adding approval rule…',
        onError: (error) => setStatus(error.message, true)
    });
    byId('approval-rule')?.addEventListener('keydown', (event) => {
        if (event.key === 'Enter') {
            event.preventDefault();
            void addRule();
        }
    });
    window.maiaUi.bindBusyClick(byId('approval-clear'), () => updateApproval('clear'), {
        busyText: 'Clearing approval rules…',
        onError: (error) => setStatus(error.message, true)
    });
    window.maiaUi.bindBusyClick(byId('approval-delete'), () => updateApproval('delete'), {
        busyText: 'Deleting approval rules…',
        onError: (error) => setStatus(error.message, true)
    });
    window.maiaUi.bindBusyClick(byId('approvals-refresh'), loadApprovals, {
        busyText: 'Refreshing approvals…',
        onError: (error) => setStatus(error.message, true)
    });
})();
