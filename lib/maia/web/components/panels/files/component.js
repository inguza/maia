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

    function resizeInput() {
        input.style.height = 'auto';
        const styles = window.getComputedStyle(input);
        const borders = (parseFloat(styles.borderTopWidth) || 0) + (parseFloat(styles.borderBottomWidth) || 0);
        input.style.height = `${input.scrollHeight + borders}px`;
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
                resizeInput();
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
            resizeInput();
            window.clearTimeout(completionTimer);
            void refreshCompletion();
        }
        input.focus();
    }

    input.addEventListener('input', () => {
        resizeInput();
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

    function parsePaths(value) {
        return value.split(/\r\n|\n|\r/).map((path) => path.trim()).filter(Boolean);
    }

    async function addKnownFiles(paths) {
        let added = 0;
        setLoading(paths.length === 1 ? `Adding ${paths[0]}...` : `Adding ${paths.length} files...`);
        try {
            for (const path of paths) {
                await window.maiaApi.request('/api/file/add', {
                    method: 'POST',
                    headers: { 'Content-Type': 'text/plain; charset=utf-8' },
                    body: path
                });
                added++;
            }
            input.value = '';
            resizeInput();
            candidates = [];
            completion.hidden = true;
            completionPending = false;
            await loadFiles();
            setStatus(paths.length === 1 ? `Added ${paths[0]}.` : `Added ${paths.length} files.`);
        } catch (error) {
            input.value = paths.slice(added).join('\n');
            resizeInput();
            candidates = [];
            completion.hidden = true;
            completionPending = false;
            completionQuery = input.value;
            await loadFiles();
            const progress = added > 0 ? ` Added ${added} of ${paths.length} files before the error.` : '';
            setStatus(`${error.message || 'Unable to add files.'}${progress}`, true);
        }
    }

    function addPaths(paths) {
        paths = paths.map((path) => String(path).trim()).filter(Boolean);
        if (paths.length === 0) {
            setStatus('Drop workspace-relative paths or enter them in the Files panel, one per line.', true);
            return;
        }
        const busyText = paths.length === 1 ? 'Adding file...' : `Adding ${paths.length} files...`;
        void window.maiaUi.runBusy(addButton, busyText, () => addKnownFiles(paths));
    }

    function hasDropData(dataTransfer) {
        const types = Array.from(dataTransfer?.types || []);
        return types.includes('Files') || types.includes('text/plain') ||
            types.includes('application/x-maia-workspace-paths+json');
    }

    function droppedPaths(dataTransfer) {
        const multiPathData = dataTransfer.getData('application/x-maia-workspace-paths+json');
        if (multiPathData) {
            try {
                const paths = JSON.parse(multiPathData);
                if (Array.isArray(paths)) {
                    const validPaths = paths.filter((path) => typeof path === 'string' && path.trim() !== '');
                    if (validPaths.length > 0) return validPaths.map((path) => path.trim());
                }
            } catch (_) {
                // Fall back to plain text when custom drag data is unavailable or invalid.
            }
        }

        const text = dataTransfer.getData('text/plain').trim();
        if (text) return parsePaths(text);

        return Array.from(dataTransfer.files || [])
            .map((file) => file.webkitRelativePath || file.name)
            .filter(Boolean);
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
        const paths = droppedPaths(event.dataTransfer);
        if (paths.length > 0) {
            window.clearTimeout(completionTimer);
            completionRequest++;
            const existingPaths = parsePaths(input.value);
            input.value = [...existingPaths, ...paths].join('\n');
            resizeInput();
            completionQuery = input.value;
            completionPending = false;
            candidates = [];
            completion.hidden = true;
            input.focus();
        }
    });

    resizeInput();

    form.addEventListener('submit', (event) => {
        event.preventDefault();
        const paths = parsePaths(input.value);
        if (paths.length === 0) {
            setStatus('Enter one or more paths relative to the workspace root, one per line.', true);
            input.focus();
            return;
        }
        addPaths(paths);
    });

    window.maiaUi.bindBusyClick(refreshButton, loadFiles, {
        busyText: 'Refreshing known files...',
        onError: (error) => setStatus(error.message || 'Unable to refresh known files.', true)
    });

    void loadFiles();
})();
