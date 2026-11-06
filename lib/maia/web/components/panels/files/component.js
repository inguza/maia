/* Session-scoped known-file management. */
(() => {
    'use strict';

    const root = document.querySelector('.known-files-panel');
    if (!root || !window.maiaApi || !window.maiaUi) return;

    const input = root.querySelector('#known-file-path');
    const form = root.querySelector('[data-known-files-form]');
    const status = root.querySelector('[data-known-files-role="status"]');
    const list = root.querySelector('[data-known-files-role="list"]');
    const completion = root.querySelector('[data-known-files-role="completion"]');
    const addButton = form?.querySelector('button[type="submit"]');
    const refreshButton = root.querySelector('[data-known-files-action="refresh"]');

    let candidates = [];
    let completionQuery = '';
    let completionRequest = 0;
    let completionTimer = null;
    let completionPending = false;

    function setStatus(message, error = false) {
        window.maiaUi.setStatus(status, message, { error });
    }

    function setLoading(message) {
        window.maiaUi.setLoadingStatus(status, message);
    }

    function renderFiles(files) {
        list.replaceChildren();
        for (const file of files) {
            const row = document.createElement('li');
            const path = document.createElement('span');
            path.textContent = file;

            const remove = document.createElement('button');
            remove.type = 'button';
            remove.textContent = '\u00D7';
            remove.setAttribute('aria-label', `Remove ${file}`);
            remove.title = `Remove ${file}`;
            window.maiaUi.bindBusyClick(remove, async () => {
                setLoading(`Removing ${file}...`);
                await window.maiaApi.request('/api/file/forget', {
                    method: 'POST',
                    headers: { 'Content-Type': 'text/plain; charset=utf-8' },
                    body: file
                });
                await loadFiles();
                setStatus(`Removed ${file}.`);
            }, {
                busyText: 'Removing file...',
                onError: (error) => setStatus(error.message || 'Unable to remove file.', true)
            });

            row.append(path, remove);
            list.appendChild(row);
        }
    }

    async function loadFiles() {
        setLoading('Loading known files...');
        try {
            const result = await window.maiaApi.request('/api/file/list');
            const files = Array.isArray(result.files) ? result.files : [];
            renderFiles(files);
            setStatus(files.length > 0 ? '' : 'No known files.');
        } catch (error) {
            // Keep the existing list on screen if refreshing fails.
            setStatus(error.message || 'Unable to load known files.', true);
        }
    }

    function showCompletionLoading() {
        completion.replaceChildren();
        const row = document.createElement('div');
        row.className = 'file-completion-loading';
        row.setAttribute('role', 'status');
        const spinner = document.createElement('span');
        spinner.className = 'spinner';
        spinner.setAttribute('aria-hidden', 'true');
        const label = document.createElement('span');
        label.textContent = 'Loading suggestions...';
        row.append(spinner, label);
        completion.appendChild(row);
        completion.hidden = false;
    }

    function renderCompletion() {
        completion.replaceChildren();
        for (const candidate of candidates) {
            const option = document.createElement('button');
            option.type = 'button';
            option.className = 'file-completion-option';
            option.textContent = candidate;
            option.setAttribute('role', 'option');
            option.addEventListener('mousedown', (event) => {
                event.preventDefault();
                window.clearTimeout(completionTimer);
                completionRequest++;
                input.value = candidate;
                completionQuery = candidate;
                candidates = [];
                if (candidate.endsWith('/')) {
                    completionPending = true;
                    void refreshCompletion();
                } else {
                    completionPending = false;
                    completion.hidden = true;
                }
                input.focus();
            });
            completion.appendChild(option);
        }
        completion.hidden = candidates.length === 0;
    }

    function commonPrefix(values) {
        if (values.length === 0) return '';
        let prefix = values[0];
        for (const value of values.slice(1)) {
            let length = 0;
            while (length < prefix.length && length < value.length && prefix[length] === value[length]) {
                length++;
            }
            prefix = prefix.slice(0, length);
        }
        return prefix;
    }

    async function refreshCompletion() {
        const value = input.value;
        const requestId = ++completionRequest;
        completionQuery = value;
        completionPending = true;
        showCompletionLoading();
        try {
            const result = await window.maiaApi.request(`/api/file/complete?path=${encodeURIComponent(value)}`);
            if (requestId !== completionRequest || input.value !== value) return;
            candidates = Array.isArray(result.candidates) ? result.candidates : [];
            renderCompletion();
        } catch (_) {
            if (requestId === completionRequest) {
                candidates = [];
                completion.hidden = true;
            }
        } finally {
            if (requestId === completionRequest) completionPending = false;
        }
    }

    function completePath() {
        if (candidates.length === 0 || completionQuery !== input.value) return;
        const value = candidates.length === 1 ? candidates[0] : commonPrefix(candidates);
        if (value && value !== input.value) {
            input.value = value;
            window.clearTimeout(completionTimer);
            void refreshCompletion();
        }
        input.focus();
    }

    input.addEventListener('input', () => {
        completionRequest++;
        candidates = [];
        completionQuery = input.value;
        completionPending = true;
        showCompletionLoading();
        window.clearTimeout(completionTimer);
        completionTimer = window.setTimeout(() => void refreshCompletion(), 100);
    });

    input.addEventListener('keydown', (event) => {
        if (event.key === 'Tab' && (input.value === '' || completionPending ||
            (completionQuery === input.value && candidates.length > 0))) {
            event.preventDefault();
            window.clearTimeout(completionTimer);
            const value = input.value;
            if (completionQuery === value && candidates.length > 0) {
                completePath();
            } else {
                void refreshCompletion().then(() => {
                    if (input.value === value) completePath();
                });
            }
        } else if (event.key === 'Escape') {
            completion.hidden = true;
        }
    });

    input.addEventListener('blur', () => {
        window.setTimeout(() => { completion.hidden = true; }, 100);
    });

    async function addKnownFile(path) {
        setLoading(`Adding ${path}...`);
        try {
            const result = await window.maiaApi.request('/api/file/add', {
                method: 'POST',
                headers: { 'Content-Type': 'text/plain; charset=utf-8' },
                body: path
            });
            input.value = '';
            candidates = [];
            completion.hidden = true;
            await loadFiles();
            setStatus(result.message || `Added ${path}.`);
        } catch (error) {
            setStatus(error.message || 'Unable to add file.', true);
        }
    }

    function addPath(path) {
        path = path.trim();
        if (!path) {
            setStatus('Drop a workspace-relative path or enter one in the Files panel.', true);
            return;
        }

        input.value = path;
        void window.maiaUi.runBusy(addButton, 'Adding file...', () => addKnownFile(path));
    }

    function hasDropData(dataTransfer) {
        const types = Array.from(dataTransfer?.types || []);
        return types.includes('Files') || types.includes('text/plain');
    }

    function droppedPath(dataTransfer) {
        const text = dataTransfer.getData('text/plain').trim();
        if (text) return text;

        const file = dataTransfer.files?.[0];
        return file ? (file.webkitRelativePath || file.name) : '';
    }

    let dragDepth = 0;
    root.addEventListener('dragenter', (event) => {
        if (!hasDropData(event.dataTransfer)) return;
        event.preventDefault();
        dragDepth++;
        root.classList.add('is-file-drop-target');
    });

    root.addEventListener('dragover', (event) => {
        if (!hasDropData(event.dataTransfer)) return;
        event.preventDefault();
        event.dataTransfer.dropEffect = 'copy';
    });

    root.addEventListener('dragleave', (event) => {
        if (!hasDropData(event.dataTransfer)) return;
        dragDepth = Math.max(0, dragDepth - 1);
        if (dragDepth === 0) root.classList.remove('is-file-drop-target');
    });

    root.addEventListener('drop', (event) => {
        if (!hasDropData(event.dataTransfer)) return;
        event.preventDefault();
        dragDepth = 0;
        root.classList.remove('is-file-drop-target');
        const path = droppedPath(event.dataTransfer).trim();
        if (path) {
            input.value = path;
            candidates = [];
            completion.hidden = true;
            input.focus();
        }
    });

    form.addEventListener('submit', (event) => {
        event.preventDefault();
        const path = input.value.trim();
        if (!path) {
            setStatus('Enter a path relative to the workspace root.', true);
            input.focus();
            return;
        }
        addPath(path);
    });

    window.maiaUi.bindBusyClick(refreshButton, loadFiles, {
        busyText: 'Refreshing known files...',
        onError: (error) => setStatus(error.message || 'Unable to refresh known files.', true)
    });

    void loadFiles();
})();
