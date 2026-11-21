/* Instructions panel behavior. */
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
        const scopedPath = typeof path === 'string' && path.startsWith('/api/instruction/')
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

    function setStatus(message, isError = false) {
        window.maiaUi.setStatus('instructions-status', message, { error: isError });
    }
    function setLoadingStatus(message) {
        window.maiaUi.setLoadingStatus('instructions-status', message);
    }
    function syncRemoveSelected() {
        byId('instruction-remove-selected').hidden = selectedPatterns.size === 0;
    }
    function makeButton(label, title, handler) {
        const button = document.createElement('button');
        button.type = 'button';
        button.textContent = label;
        button.title = title;
        button.setAttribute('aria-label', title);
        button.className = 'small-action';
        button.addEventListener('click', () => Promise.resolve(handler()).catch((error) => setStatus(error.message, true)));
        return button;
    }
    async function request(action, pattern = '', replacement = '') {
        return api('/api/instruction/context?scope=home', jsonOptions({ action, pattern, replacement }));
    }
    async function reloadAfter(action, pattern = '', replacement = '', success = '') {
        try {
            await request(action, pattern, replacement);
            loaded = false;
            const result = await loadInstructions();
            if (result) setStatus(success);
        } catch (error) {
            loaded = false;
            await loadInstructions();
            setStatus(error.message, true);
        }
    }
    async function removePattern(pattern, row) {
        row.remove();
        selectedPatterns.delete(pattern);
        syncRemoveSelected();
        await reloadAfter('disable', pattern, '', `Removed ${pattern}.`);
    }
    async function editPattern(pattern, replacement) {
        await reloadAfter('change', pattern, replacement, `Updated ${pattern}.`);
    }
    async function addPattern(value = '') {
        const input = byId('instruction-pattern');
        const pattern = (value || input.value).trim();
        if (!pattern) return;
        await reloadAfter('append', pattern, '', `Added ${pattern}.`);
        input.value = '';
    }
    async function clearOrDelete(action) {
        await reloadAfter(action, '', '', action === 'clear' ? 'Cleared selections for this scope.' : 'Deleted selections for this scope.');
    }
    async function removeSelectedPatterns() {
        const patterns = [...selectedPatterns];
        if (!patterns.length) return;
        selectedPatterns.clear();
        syncRemoveSelected();
        let failures = [];
        for (const pattern of patterns) {
            try { await request('disable', pattern); }
            catch (error) { failures.push(`${pattern}: ${error.message}`); }
        }
        loaded = false;
        await loadInstructions();
        if (failures.length) setStatus(`Unable to remove: ${failures.join('; ')}`, true);
        else setStatus(`Removed ${patterns.length} pattern${patterns.length === 1 ? '' : 's'}.`);
    }
    function renderPatterns(patterns) {
        const list = byId('instruction-pattern-list');
        list.replaceChildren();
        selectedPatterns.clear();
        for (const pattern of patterns) {
            const item = document.createElement('li');
            const checkbox = document.createElement('input');
            checkbox.type = 'checkbox';
            checkbox.className = 'item-selector';
            checkbox.setAttribute('aria-label', `Select ${pattern}`);
            checkbox.addEventListener('change', () => {
                if (checkbox.checked) selectedPatterns.add(pattern);
                else selectedPatterns.delete(pattern);
                syncRemoveSelected();
            });
            const text = document.createElement('span');
            text.className = 'item-label';
            text.textContent = pattern;
            let editInput = null;
            let removeButton;
            const editButton = makeButton('\u270E', `Edit ${pattern}`, () => {
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
                checkbox.hidden = true;
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
                editInput.focus(); editInput.select();
            });
            removeButton = makeButton('\u00D7', `Remove ${pattern}`, () => {
                if (editInput) {
                    const replacement = editInput.value.trim();
                    if (!replacement) { editInput.focus(); return; }
                    if (replacement === pattern) { editButton.click(); return; }
                    return editPattern(pattern, replacement);
                }
                return removePattern(pattern, item);
            });
            item.append(checkbox, text, editButton, removeButton);
            list.appendChild(item);
        }
        syncRemoveSelected();
    }
    function conditionSummary(instruction) {
        const conditions = instruction.conditions || {};
        const labels = Object.entries(conditions).map(([key, value]) => `${key}: ${value}`);
        if (instruction.autoload) labels.unshift('autoload: always/conditional');
        else labels.unshift('autoload: off');
        return labels.join(' · ');
    }
    function renderAvailable(instructions) {
        const list = byId('available-instructions-list');
        const heading = list.querySelector('.available-resource-heading');
        list.replaceChildren();
        if (heading) list.appendChild(heading);
        for (const instruction of instructions.filter((item) => item.allowed)) {
            const row = document.createElement('li');
            const detail = document.createElement('span');
            detail.className = 'available-resource-name';
            const name = document.createElement('strong');
            name.textContent = instruction.name;
            const description = document.createElement('span');
            description.textContent = instruction.description ? ` — ${instruction.description}` : '';
            const metadata = document.createElement('small');
            metadata.className = 'muted';
            metadata.textContent = conditionSummary(instruction);
            detail.append(name, description, document.createElement('br'), metadata);
            const action = instruction.selected
                ? Object.assign(document.createElement('span'), { textContent: 'Selected' })
                : makeButton('Add', `Select ${instruction.name}`, () => addPattern(instruction.name));
            row.append(detail, action);
            list.appendChild(row);
        }
        if (list.children.length === (heading ? 1 : 0)) {
            const empty = document.createElement('li');
            empty.textContent = 'No available instructions.';
            list.appendChild(empty);
        }
    }
    async function loadInstructions() {
        byId('instruction-delete').hidden = true;
        setLoadingStatus('Loading instructions…');
        try {
            const result = await api('/api/instruction/context?scope=home');
            const scope = result.scope || 'default';
            byId('instructions-scope').textContent = `Instruction scope '${scope}'`;
            byId('instruction-delete').hidden = scope !== (result.targetScope || currentContextScope());
            const patterns = Array.isArray(result.patterns) ? result.patterns : [];
            renderPatterns(patterns);
            renderAvailable(Array.isArray(result.instructions) ? result.instructions : []);
            setStatus(patterns.length ? '' : 'No explicitly selected instruction patterns.');
            loaded = true;
            return true;
        } catch (error) {
            setStatus(error.message || 'Unable to load instructions.', true);
            return false;
        }
    }
    document.addEventListener('maia:panel-open', (event) => {
        if (event.detail?.id === 'instructions' && !loaded) void loadInstructions();
    });
    window.maiaUi.bindBusyClick(byId('instruction-pattern-add'), () => addPattern(), {
        busyText: 'Adding instruction pattern…', onError: (error) => setStatus(error.message, true)
    });
    byId('instruction-pattern')?.addEventListener('keydown', (event) => {
        if (event.key === 'Enter') { event.preventDefault(); void addPattern(); }
    });
    window.maiaUi.bindBusyClick(byId('instruction-remove-selected'), removeSelectedPatterns, {
        busyText: 'Removing selected instruction patterns…', onError: (error) => setStatus(error.message, true)
    });
    window.maiaUi.bindBusyClick(byId('instruction-clear'), () => clearOrDelete('clear'), {
        busyText: 'Clearing instruction selections…', onError: (error) => setStatus(error.message, true)
    });
    window.maiaUi.bindBusyClick(byId('instruction-delete'), () => clearOrDelete('delete'), {
        busyText: 'Deleting instruction selections…', onError: (error) => setStatus(error.message, true)
    });
    window.maiaUi.bindBusyClick(byId('instructions-refresh'), async () => {
        loaded = false;
        await loadInstructions();
    }, { busyText: 'Refreshing instructions…', onError: (error) => setStatus(error.message, true) });
})();
