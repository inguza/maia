/* Session-scoped change suggestions and actions. */
(() => {
    'use strict';

    const root = document.querySelector('.changes-panel');
    if (!root || !window.maiaApi || !window.maiaUi) return;

    const list = root.querySelector('[data-changes-role="list"]');
    const status = root.querySelector('[data-changes-role="status"]');
    const stateFilter = root.querySelector('[data-changes-filter="state"]');
    const typeFilter = root.querySelector('[data-changes-filter="type"]');
    const refresh = root.querySelector('[data-changes-action="refresh"]');
    const states = ['pending', 'running', 'applied', 'skipped', 'finished', 'failed'];
    const checkedValues = (container) => new Set(
        Array.from(container.querySelectorAll('input[type="checkbox"]:checked'), (input) => input.value)
    );
    const selectedStates = checkedValues(stateFilter);
    const selectedTypes = checkedValues(typeFilter);
    let changes = [];
    let loaded = false;

    function titleCase(value) {
        return value ? value[0].toUpperCase() + value.slice(1) : value;
    }

    function setStatus(message, error = false) {
        window.maiaUi.setStatus(status, message, { error });
    }

    function setLoading(message) {
        window.maiaUi.setLoadingStatus(status, message);
    }

    function changePageUrl(id) {
        const session = String(document.body.dataset.maiaSession || '');
        return window.maiaApi.url(`/changes/${encodeURIComponent(session)}/${encodeURIComponent(id)}`);
    }

    function fitMiddleEllipsis(path) {
        const directory = path.querySelector('.change-directory');
        if (!(directory instanceof HTMLElement)) return;
        const fullPath = directory.dataset.fullPath || '';
        directory.textContent = fullPath;
        if (!fullPath || directory.clientWidth <= 0 || directory.scrollWidth <= directory.clientWidth) return;

        const characters = Array.from(fullPath);
        let low = 0;
        let high = characters.length - 1;
        let best = '…';
        while (low <= high) {
            const keep = Math.floor((low + high) / 2);
            const prefixLength = Math.ceil(keep / 2);
            const suffixLength = Math.floor(keep / 2);
            const candidate = `${characters.slice(0, prefixLength).join('')}…${suffixLength ? characters.slice(-suffixLength).join('') : ''}`;
            directory.textContent = candidate;
            if (directory.scrollWidth <= directory.clientWidth) {
                best = candidate;
                low = keep + 1;
            } else {
                high = keep - 1;
            }
        }
        directory.textContent = best;
    }

    const pathObserver = typeof ResizeObserver === 'function'
        ? new ResizeObserver((entries) => entries.forEach((entry) => fitMiddleEllipsis(entry.target)))
        : null;
    if (!pathObserver) {
        window.addEventListener('resize', () => {
            list.querySelectorAll('.change-path').forEach(fitMiddleEllipsis);
        }, { passive: true });
    }

    function bindAction(button, id, action, busyText) {
        window.maiaUi.bindBusyClick(button, async () => {
            if (action === 'do' && !window.confirm(`Run the proposed action for change ${id}?`)) return;
            setLoading(`${titleCase(action)} change...`);
            const result = await window.maiaApi.request('/api/change/action', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ id, action })
            });
            await loadChanges();
            setStatus(result.message || 'Updated change.');
        }, {
            busyText,
            onError: (error) => setStatus(error.message || `Unable to ${action} change.`, true)
        });
    }

    function makeActionButton(parent, label, id, action) {
        const button = document.createElement('button');
        button.type = 'button';
        button.textContent = label;
        button.title = `${label} change`;
        button.setAttribute('aria-label', `${label} change`);
        parent.appendChild(button);
        bindAction(button, id, action, `${label}...`);
    }

    function renderPreview(details, preview, change) {
        let loadedDetail = false;
        let loadingDetail = false;
        details.addEventListener('toggle', async () => {
            if (!details.open || loadedDetail || loadingDetail) return;
            loadingDetail = true;
            preview.textContent = 'Loading change details...';
            try {
                const result = await window.maiaApi.request(`/api/change/show?id=${encodeURIComponent(change.id)}`);
                preview.textContent = String(result.detail || '(No change details.)');
                loadedDetail = true;
            } catch (error) {
                preview.textContent = error.message || 'Unable to load change details. Close and reopen to retry.';
            } finally {
                loadingDetail = false;
            }
        });
    }

    function rowFor(change) {
        const row = document.createElement('article');
        row.className = 'change-row';

        const previewDetails = document.createElement('details');
        previewDetails.className = 'change-preview';
        const summary = document.createElement('summary');
        const previewLine = document.createElement('span');
        previewLine.className = 'change-preview-line';
        const changeLink = document.createElement('a');
        changeLink.className = 'change-id-link';
        const idParts = change.id.split('-');
        const shortId = idParts.length >= 3 ? idParts.slice(-2).join('-') : change.id;
        changeLink.href = changePageUrl(change.id);
        changeLink.textContent = shortId;
        changeLink.title = `Open full details for change ${change.id}`;
        changeLink.addEventListener('click', (event) => event.stopPropagation());
        previewLine.appendChild(changeLink);

        const filename = String(change.filename || '');
        if (filename !== '') {
            const separator = Math.max(filename.lastIndexOf('/'), filename.lastIndexOf('\\\\'));
            const directoryText = separator >= 0 ? filename.slice(0, separator + 1) : '';
            const basename = filename.slice(separator + 1);
            const path = document.createElement('span');
            path.className = 'change-path';
            const directory = document.createElement('span');
            directory.className = 'change-directory';
            directory.dataset.fullPath = directoryText;
            directory.textContent = directoryText;
            path.appendChild(directory);
            if (typeof change.fileUrl === 'string' && change.fileUrl !== '') {
                const fileLink = document.createElement('a');
                fileLink.className = 'change-filename';
                fileLink.href = change.fileUrl;
                fileLink.textContent = basename;
                fileLink.title = `View ${filename}`;
                fileLink.addEventListener('click', (event) => event.stopPropagation());
                path.appendChild(fileLink);
            } else {
                const fileLabel = document.createElement('span');
                fileLabel.className = 'change-filename';
                fileLabel.textContent = basename;
                path.appendChild(fileLabel);
            }
            previewLine.appendChild(path);
            if (pathObserver) pathObserver.observe(path);
        }
        const type = document.createElement('a');
        type.className = 'change-type-link';
        type.href = changePageUrl(change.id);
        type.textContent = `(${change.type})`;
        type.title = `Open full details for change ${change.id}`;
        type.addEventListener('click', (event) => event.stopPropagation());
        previewLine.appendChild(type);
        summary.appendChild(previewLine);

        const preview = document.createElement('pre');
        preview.className = 'change-preview-content';
        previewDetails.append(summary, preview);
        renderPreview(previewDetails, preview, change);
        row.appendChild(previewDetails);

        const stateControl = document.createElement('div');
        stateControl.className = 'change-state';
        const select = document.createElement('select');
        select.setAttribute('aria-label', `Set state for ${change.id}`);
        for (const state of states) {
            const option = document.createElement('option');
            option.value = state;
            option.textContent = titleCase(state);
            option.selected = state === change.state;
            select.appendChild(option);
        }
        stateControl.appendChild(select);
        const stateButton = document.createElement('button');
        stateButton.type = 'button';
        stateButton.textContent = 'Set';
        stateButton.title = 'Set change state';
        stateButton.setAttribute('aria-label', 'Set change state');
        stateControl.appendChild(stateButton);
        window.maiaUi.bindBusyClick(stateButton, async () => {
            setLoading('Updating change...');
            const result = await window.maiaApi.request('/api/change/action', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ id: change.id, action: select.value })
            });
            await loadChanges();
            setStatus(result.message || 'Change state updated.');
        }, {
            busyText: 'Updating...',
            onError: (error) => setStatus(error.message || 'Unable to update change state.', true)
        });
        row.appendChild(stateControl);

        const actions = document.createElement('div');
        actions.className = 'change-actions';
        if (change.type === 'patch' && change.state === 'pending') {
            makeActionButton(actions, 'Apply', change.id, 'apply');
        } else if (change.type === 'patch' && change.state === 'applied') {
            makeActionButton(actions, 'Revert', change.id, 'revert');
        } else if ((change.type === 'shell' || change.type === 'action') && change.state === 'pending') {
            makeActionButton(actions, 'Do', change.id, 'do');
        }
        if (actions.childElementCount) row.appendChild(actions);
        return row;
    }

    function addTypeFilter(type) {
        if (typeFilter.querySelector(`input[value="${CSS.escape(type)}"]`)) return;
        const label = document.createElement('label');
        const checkbox = document.createElement('input');
        checkbox.type = 'checkbox';
        checkbox.value = type;
        checkbox.checked = true;
        selectedTypes.add(type);
        label.append(checkbox, document.createTextNode(titleCase(type)));
        typeFilter.appendChild(label);
    }

    function renderTypeFilters() {
        for (const type of [...new Set(changes.map((change) => change.type).filter((type) => type !== 'set'))].sort()) {
            addTypeFilter(type);
        }
    }

    function renderChanges() {
        pathObserver?.disconnect();
        list.replaceChildren();
        if (!loaded && changes.length === 0) return;
        const visible = changes.filter((change) =>
            change.type !== 'set' && selectedStates.has(change.state) && selectedTypes.has(change.type)
        );
        if (visible.length === 0) {
            const empty = document.createElement('p');
            empty.className = 'change-empty';
            empty.textContent = changes.length ? 'No changes match the selected filters.' : 'No changes for this session.';
            list.appendChild(empty);
            return;
        }

        const groups = new Map();
        for (const change of visible) {
            const match = change.id.match(/^(.*)-\d{1,3}$/);
            const base = match ? match[1] : change.id;
            if (!groups.has(base)) groups.set(base, []);
            groups.get(base).push(change);
        }
        const orderedGroups = [...groups.entries()].sort(([first], [second]) => second.localeCompare(first));
        for (const [base, members] of orderedGroups) {
            members.sort((first, second) => {
                const firstNumber = Number(first.id.match(/-(\d{1,3})$/)?.[1] || -1);
                const secondNumber = Number(second.id.match(/-(\d{1,3})$/)?.[1] || -1);
                return secondNumber - firstNumber || second.id.localeCompare(first.id);
            });
            const set = document.createElement('details');
            set.className = 'change-set';
            set.open = true;
            const summary = document.createElement('summary');
            summary.textContent = base;
            const body = document.createElement('div');
            body.className = 'change-set-body';
            for (const change of members) body.appendChild(rowFor(change));
            set.append(summary, body);
            list.appendChild(set);
        }
    }

    async function loadChanges() {
        setLoading('Loading changes...');
        try {
            const result = await window.maiaApi.request('/api/change/list');
            changes = Array.isArray(result.changes) ? result.changes : [];
            renderTypeFilters();
            renderChanges();
            setStatus('');
            loaded = true;
        } catch (error) {
            setStatus(error.message || 'Unable to load changes.', true);
        }
    }

    stateFilter.addEventListener('change', (event) => {
        const checkbox = event.target;
        if (checkbox instanceof HTMLInputElement && checkbox.type === 'checkbox') {
            checkbox.checked ? selectedStates.add(checkbox.value) : selectedStates.delete(checkbox.value);
            renderChanges();
        }
    });
    typeFilter.addEventListener('change', (event) => {
        const checkbox = event.target;
        if (checkbox instanceof HTMLInputElement && checkbox.type === 'checkbox') {
            checkbox.checked ? selectedTypes.add(checkbox.value) : selectedTypes.delete(checkbox.value);
            renderChanges();
        }
    });
    window.maiaUi.bindBusyClick(refresh, loadChanges, {
        busyText: 'Refreshing changes...',
        onError: (error) => setStatus(error.message || 'Unable to refresh changes.', true)
    });
    document.addEventListener('maia:panel-open', (event) => {
        if (event.detail?.id !== 'changes') return;
        requestAnimationFrame(() => list.querySelectorAll('.change-path').forEach(fitMiddleEllipsis));
        if (!loaded) void loadChanges();
    });
})();
