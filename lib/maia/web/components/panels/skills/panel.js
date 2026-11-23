/* Skills panel behavior. */
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

    const api = (path, ...args) => window.maiaApi.request(path, ...args);
    const contextUrl = (scope) => `/api/skill/context?scope=${encodeURIComponent(scope)}`;
    const jsonOptions = (body) => ({
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
    });
    let loaded = false;
    let allowedScope = currentContextScope();
    let allowedSourceScope = 'default';
    let memoryScope = 'default';
    let memoryTargetScope = currentContextScope();
    const selectedPatterns = new Set();
    const pendingListOperations = new Set();
    const completedListOperations = [];
    let finalizingListOperations = false;

    function syncRemoveSelected() {
        byId('skill-remove-selected').hidden = selectedPatterns.size === 0;
    }

    function beginListOperation(type, label, rows = [], count = 1) {
        const operation = { type, label, count, error: '', success: '' };
        pendingListOperations.add(operation);
        if (type === 'edit') {
            selectedPatterns.delete(label);
            syncRemoveSelected();
        }
        for (const row of rows) row.querySelectorAll('input, button').forEach((control) => { control.disabled = true; });
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
        const refreshed = await loadSkills();
        const results = completedListOperations.splice(0);
        finalizingListOperations = false;
        const errors = results.filter((result) => result.error).map((result) => result.error);
        if (errors.length) setStatus(`Unable to complete: ${errors.join('; ')}`, true);
        else if (refreshed) setStatus(results.at(-1)?.success || '');
    }

    function setStatus(message, isError = false) {
        window.maiaUi.setStatus('skills-status', message, { error: isError });
    }

    function setLoadingStatus(message) {
        window.maiaUi.setLoadingStatus('skills-status', message);
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
            let editButton;
            let removeButton;
            editButton = makeButton('\u270E', `Edit ${pattern}`, () => {
                if (editInput) {
                    editInput.remove(); editInput = null;
                    item.classList.remove('is-editing');
                    checkbox.hidden = false; text.hidden = false;
                    editButton.textContent = '\u270E';
                    editButton.title = `Edit ${pattern}`;
                    editButton.setAttribute('aria-label', `Edit ${pattern}`);
                    removeButton.textContent = '\u00D7';
                    removeButton.title = `Remove ${pattern}`;
                    removeButton.setAttribute('aria-label', `Remove ${pattern}`);
                    return;
                }
                selectedPatterns.delete(pattern);
                checkbox.checked = false; checkbox.hidden = true; syncRemoveSelected();
                editInput = document.createElement('input');
                editInput.type = 'text'; editInput.className = 'item-edit-input'; editInput.value = pattern;
                editInput.setAttribute('aria-label', `Edit ${pattern}`);
                editInput.addEventListener('keydown', (event) => {
                    if (event.key === 'Enter') { event.preventDefault(); removeButton.click(); }
                    if (event.key === 'Escape') { event.preventDefault(); editButton.click(); }
                });
                text.hidden = true; item.insertBefore(editInput, text); item.classList.add('is-editing');
                editButton.textContent = '\u21B6';
                editButton.title = `Cancel editing ${pattern}`;
                editButton.setAttribute('aria-label', `Cancel editing ${pattern}`);
                removeButton.textContent = '\u2713';
                removeButton.title = `Save ${pattern}`;
                removeButton.setAttribute('aria-label', `Save ${pattern}`);
                editInput.focus(); editInput.select();
            });
            removeButton = makeButton('\u00D7', `Remove ${pattern}`, () => {
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

    async function requestSkill(action, pattern = '', replacement = '') {
        // Allow-list edits belong to the page's scope, even when the effective
        // allowed definition is inherited from a parent scope.
        return api(contextUrl(currentContextScope()), jsonOptions({ action, ...(pattern ? { pattern } : {}), ...(replacement ? { replacement } : {}) }));
    }

    async function updateSkill(action, pattern = '', replacement = '') {
        try {
            await requestSkill(action, pattern, replacement);
            loaded = false;
            await loadSkills();
        } catch (error) {
            loaded = false;
            await loadSkills();
            setStatus(error.message, true);
        }
    }

    async function removeSkill(pattern, item) {
        item.remove();
        selectedPatterns.delete(pattern);
        syncRemoveSelected();
        const operation = beginListOperation('remove', pattern);
        try {
            await requestSkill('disable', pattern);
            await finishListOperation(operation, null, `Removed ${pattern}.`);
        } catch (error) { await finishListOperation(operation, error); }
    }

    async function editSkill(pattern, replacement, item) {
        const operation = beginListOperation('edit', pattern, [item]);
        try {
            await requestSkill('change', pattern, replacement.trim());
            await finishListOperation(operation, null, `Updated ${pattern}.`);
        } catch (error) { await finishListOperation(operation, error); }
    }

    async function removeSelectedSkills() {
        const patterns = [...selectedPatterns];
        [...byId('skill-pattern-list').children]
            .filter((row) => selectedPatterns.has(row.querySelector('.item-label')?.textContent))
            .forEach((row) => row.remove());
        selectedPatterns.clear();
        syncRemoveSelected();
        const operation = beginListOperation('remove', `${patterns.length} patterns`, [], patterns.length);
        const failures = [];
        for (const pattern of patterns) {
            try { await requestSkill('disable', pattern); }
            catch (error) { failures.push(`${pattern}: ${error.message}`); }
        }
        await finishListOperation(operation, failures.length ? new Error(failures.join('; ')) : null,
            `Removed ${patterns.length} pattern${patterns.length === 1 ? '' : 's'}.`);
    }

    async function updateMemory(name, remember, availableRow = null) {
        const operation = availableRow ? beginListOperation('available', name, [availableRow]) : null;
        try {
            await api(contextUrl(memoryTargetScope), jsonOptions({ action: 'memory', name, remember }));
            if (operation) await finishListOperation(operation, null, `${remember ? 'Loaded' : 'Removed'} ${name} ${remember ? 'into' : 'from'} memory.`);
            else {
                loaded = false;
                await loadSkills();
            }
        } catch (error) {
            if (operation) await finishListOperation(operation, error);
            else setStatus(error.message, true);
        }
    }

    async function addSkill(pattern, availableRow = null) {
        const input = byId('skill-pattern');
        const value = (pattern || input.value).trim();
        if (!value) return;
        if (availableRow) {
            const operation = beginListOperation('available', value, [availableRow]);
            try {
                await requestSkill('append', value);
                await finishListOperation(operation, null, `Allowed ${value}.`);
            } catch (error) { await finishListOperation(operation, error); }
        } else {
            await updateSkill('append', value);
        }
        if (input) input.value = '';
    }

    async function loadSkills() {
        if (pendingListOperations.size > 0 && !finalizingListOperations) return false;
        byId('skill-delete').hidden = true;
        setLoadingStatus('Loading skills\u2026');
        try {
            const result = await api(contextUrl(currentContextScope()));
            allowedScope = result.allowedScope || result.scope || currentContextScope();
            allowedSourceScope = result.allowedSourceScope || allowedScope;
            memoryScope = result.memorySourceScope || result.memoryScope || 'default';
            memoryTargetScope = result.memoryTargetScope || currentContextScope();
            byId('skills-scope').textContent = `Allowed scope '${allowedSourceScope}' | Memory scope '${memoryScope}'`; 
            // Delete applies to page-local settings. Keep it available when
            // either the allowed definition or memory scope is this page,
            // even if the other definition is inherited from a parent scope.
            const pageScope = currentContextScope();
            byId('skill-delete').hidden = allowedSourceScope !== pageScope && memoryScope !== pageScope;
            renderPatterns(byId('skill-pattern-list'), result.patterns || [], removeSkill, editSkill);
            const list = byId('available-skills-list');
            const heading = list.querySelector('.available-resource-heading');
            list.replaceChildren();
            if (heading) list.appendChild(heading);
            for (const skill of result.skills || []) {
                const item = document.createElement('li');
                const label = document.createElement('span');
                label.textContent = skill.description ? `${skill.name} — ${skill.description}` : skill.name;
                const allowed = skill.allowed
                    ? Object.assign(document.createElement('span'), { textContent: 'Yes' })
                    : makeButton('No', `Allow ${skill.name}`, () => addSkill(skill.name, item));
                const memory = makeButton(skill.memory ? 'Yes' : 'No',
                    skill.memory ? `Remove ${skill.name} from memory` : `Load ${skill.name} into memory`,
                    () => updateMemory(skill.name, !skill.memory, item));
                memory.disabled = !skill.allowed;
                item.append(label, allowed, memory);
                list.appendChild(item);
            }
            if (list.children.length === (heading ? 1 : 0)) {
                const empty = document.createElement('li');
                empty.textContent = 'No available skills.';
                list.appendChild(empty);
            }
            setStatus(result.patterns?.length ? '' : 'No skill patterns configured.');
            loaded = true;
            return true;
        } catch (error) { setStatus(error.message, true); return false; }
    }

    document.addEventListener('maia:panel-open', (event) => {
        if (event.detail?.id === 'skills' && !loaded) loadSkills();
    });
    window.maiaUi.bindBusyClick(byId('skill-pattern-add'), () => addSkill(), {
        busyText: 'Adding skill pattern\u2026',
        onError: (error) => setStatus(error.message, true)
    });
    byId('skill-pattern')?.addEventListener('keydown', (event) => {
        if (event.key === 'Enter') { event.preventDefault(); addSkill(); }
    });
    window.maiaUi.bindBusyClick(byId('skill-remove-selected'), removeSelectedSkills, {
        busyText: 'Removing selected skill patterns…',
        onError: (error) => setStatus(error.message, true)
    });
    window.maiaUi.bindBusyClick(byId('skill-clear'), () => updateSkill('clear'), {
        busyText: 'Clearing skill patterns\u2026',
        onError: (error) => setStatus(error.message, true)
    });
    window.maiaUi.bindBusyClick(byId('skill-delete'), () => updateSkill('delete'), {
        busyText: 'Deleting skill patterns\u2026',
        onError: (error) => setStatus(error.message, true)
    });
    window.maiaUi.bindBusyClick(byId('skills-refresh'), async () => {
        await api(contextUrl(memoryTargetScope), jsonOptions({ action: 'refresh' }));
        loaded = false;
        await loadSkills();
    }, {
        busyText: 'Refreshing skills\u2026',
        onError: (error) => setStatus(error.message, true)
    });
})();
