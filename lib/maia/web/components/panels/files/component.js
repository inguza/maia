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
    const removePatternButton = form?.querySelector('[data-known-files-action="remove-pattern"]');
    const refreshButton = root.querySelector('[data-known-files-action="refresh"]');
    const clearButton = root.querySelector('[data-known-files-action="clear"]');

    let candidates = [];
    let completionQuery = '';
    let completionRequest = 0;
    let completionTimer = null;
    let completionPending = false;
    const selectedFiles = new Set();
    const pendingListOperations = new Set();
    const completedListOperations = [];
    let finalizingListOperations = false;

    function syncRemoveSelected() {
        root.querySelector('[data-known-files-action="remove-selected"]').hidden = selectedFiles.size === 0;
    }

    function beginListOperation(type, label, row = null, count = 1) {
        const operation = { type, label, count, error: '', success: '' };
        pendingListOperations.add(operation);
        if (type === 'edit') {
            selectedFiles.delete(label);
            syncRemoveSelected();
        }
        if (row) row.querySelectorAll('input, button').forEach((control) => { control.disabled = true; });
        syncPendingStatus();
        return operation;
    }

    function syncPendingStatus() {
        const operations = [...pendingListOperations];
        const removing = operations.filter((operation) => operation.type === 'remove');
        const editing = operations.filter((operation) => operation.type === 'edit');
        const removeCount = removing.reduce((total, operation) => total + operation.count, 0);
        const editCount = editing.reduce((total, operation) => total + operation.count, 0);
        if (removeCount > 1) setLoading(`Removing ${removeCount} entries...`);
        else if (removeCount === 1) setLoading(`Removing ${removing[0].label}.`);
        else if (editCount === 1) setLoading(`Updating ${editing[0].label}...`);
        else if (editCount > 1) setLoading(`Updating ${editCount} entries...`);
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
        const refreshed = await loadFiles();
        const results = completedListOperations.splice(0);
        finalizingListOperations = false;
        const errors = results.filter((result) => result.error).map((result) => result.error);
        if (errors.length) setStatus(`Unable to complete: ${errors.join('; ')}`, true);
        else if (refreshed) setStatus(results.at(-1)?.success || '');
    }

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

    function currentLine() {
        const value = input.value;
        const cursor = input.selectionStart ?? value.length;
        const previousNewline = cursor > 0 ? value.lastIndexOf('\n', cursor - 1) : -1;
        const start = previousNewline + 1;
        const nextNewline = value.indexOf('\n', cursor);
        const end = nextNewline < 0 ? value.length : nextNewline;
        return { value: value.slice(start, end), start, end };
    }

    function replaceCurrentLine(value) {
        const line = currentLine();
        input.value = `${input.value.slice(0, line.start)}${value}${input.value.slice(line.end)}`;
        const cursor = line.start + value.length;
        input.setSelectionRange(cursor, cursor);
        resizeInput();
    }

    function formatFileSize(sizeBytes) {
        if (!Number.isFinite(sizeBytes) || sizeBytes < 0) return '—';
        if (sizeBytes < 1024) return `${sizeBytes} B`;
        const units = ['KB', 'MB', 'GB', 'TB'];
        let size = sizeBytes / 1024;
        let unit = units[0];
        for (let index = 1; size >= 1024 && index < units.length; index++) {
            size /= 1024;
            unit = units[index];
        }
        return `${size.toFixed(size >= 10 ? 0 : 1)} ${unit}`;
    }

    function renderFiles(entries) {
        list.replaceChildren();
        for (const entry of entries) {
            const file = typeof entry === 'string' ? entry : entry.path;
            const sizeBytes = typeof entry === 'string' ? null : entry.sizeBytes;
            const row = document.createElement('li');
            const checkbox = document.createElement('input');
            checkbox.type = 'checkbox';
            checkbox.className = 'known-files-selector';
            checkbox.checked = selectedFiles.has(file);
            checkbox.setAttribute('aria-label', `Select ${file}`);
            checkbox.addEventListener('change', () => {
                if (checkbox.disabled) return;
                if (checkbox.checked) selectedFiles.add(file);
                else selectedFiles.delete(file);
                syncRemoveSelected();
            });
            const path = document.createElement('span');
            path.className = 'known-files-path';
            path.textContent = file;

            const size = document.createElement('span');
            size.className = 'known-files-size';
            size.textContent = formatFileSize(sizeBytes);
            size.setAttribute('aria-label', sizeBytes === null ? 'Size unavailable' : `File size ${size.textContent}`);
            const selectedLines = file.match(/:(\d+(?:-\d*)?)(?=\||$)/);
            if (selectedLines) {
                size.title = `Full-file size; not just selected lines ${selectedLines[1]}.`;
            }

            let editInput = null;
            const edit = document.createElement('button');
            edit.type = 'button';
            edit.textContent = '\u270E';
            edit.title = `Edit ${file}`;
            edit.setAttribute('aria-label', `Edit ${file}`);

            const remove = document.createElement('button');
            remove.type = 'button';
            remove.textContent = '\u00D7';
            remove.setAttribute('aria-label', `Remove pattern ${file}`);
            remove.title = `Remove pattern ${file}`;

            function cancelEditing() {
                editInput?.remove();
                editInput = null;
                row.classList.remove('is-editing');
                checkbox.hidden = false;
                path.hidden = false;
                size.hidden = false;
                edit.textContent = '\u270E';
                edit.title = `Edit ${file}`;
                edit.setAttribute('aria-label', `Edit ${file}`);
                remove.textContent = '\u00D7';
                remove.title = `Remove pattern ${file}`;
                remove.setAttribute('aria-label', `Remove pattern ${file}`);
            }

            edit.addEventListener('click', () => {
                if (editInput) { cancelEditing(); return; }
                selectedFiles.delete(file);
                checkbox.checked = false;
                checkbox.hidden = true;
                syncRemoveSelected();
                editInput = document.createElement('input');
                editInput.type = 'text';
                editInput.className = 'item-edit-input';
                editInput.value = file;
                editInput.setAttribute('aria-label', `Edit ${file}`);
                editInput.addEventListener('keydown', (event) => {
                    if (event.key === 'Enter') { event.preventDefault(); remove.click(); }
                    if (event.key === 'Escape') { event.preventDefault(); cancelEditing(); }
                });
                path.hidden = true;
                size.hidden = true;
                row.insertBefore(editInput, path);
                row.classList.add('is-editing');
                edit.textContent = '\u21B6';
                edit.title = `Cancel editing ${file}`;
                edit.setAttribute('aria-label', `Cancel editing ${file}`);
                remove.textContent = '\u2713';
                remove.title = `Save ${file}`;
                remove.setAttribute('aria-label', `Save ${file}`);
                editInput.focus();
                editInput.select();
            });
            remove.addEventListener('click', async () => {
                if (editInput) {
                    const replacement = editInput.value.trim();
                    if (!replacement) { editInput.focus(); return; }
                    if (replacement === file) { cancelEditing(); return; }
                    await editKnownFile(file, replacement, row);
                    return;
                }
                await removeKnownFile(file, row);
            });

            row.append(checkbox, path, size, edit, remove);
            list.appendChild(row);
        }
        syncRemoveSelected();
    }

    async function forgetRequest(pattern) {
        return window.maiaApi.request('/api/file/forget', {
            method: 'POST', headers: { 'Content-Type': 'text/plain; charset=utf-8' }, body: pattern
        });
    }

    async function forgetPattern(pattern) {
        const operation = beginListOperation('remove', pattern);
        try {
            await forgetRequest(pattern);
            await finishListOperation(operation, null, `Removed pattern ${pattern}.`);
        } catch (error) { await finishListOperation(operation, error); }
    }

    async function removeKnownFile(file, row) {
        row.remove(); selectedFiles.delete(file); syncRemoveSelected();
        const operation = beginListOperation('remove', file);
        try {
            await forgetRequest(file);
            await finishListOperation(operation, null, `Removed ${file}.`);
        } catch (error) { await finishListOperation(operation, error); }
    }

    async function editKnownFile(file, replacement, row) {
        const operation = beginListOperation('edit', file, row);
        try {
            await window.maiaApi.request('/api/file/add', { method: 'POST', headers: { 'Content-Type': 'text/plain; charset=utf-8' }, body: replacement });
            await forgetRequest(file);
            await finishListOperation(operation, null, `Updated ${file}.`);
        } catch (error) { await finishListOperation(operation, error); }
    }

    async function removeSelectedFiles() {
        const files = [...selectedFiles];
        [...list.children].filter((row) => selectedFiles.has(row.querySelector('.known-files-path')?.textContent)).forEach((row) => row.remove());
        selectedFiles.clear(); syncRemoveSelected();
        const operation = beginListOperation('remove', `${files.length} files`, null, files.length);
        const failures = [];
        for (const file of files) { try { await forgetRequest(file); } catch (error) { failures.push(`${file}: ${error.message}`); } }
        await finishListOperation(operation, failures.length ? new Error(failures.join('; ')) : null,
            `Removed ${files.length} file${files.length === 1 ? '' : 's'}.`);
    }

    async function loadFiles() {
        if (pendingListOperations.size > 0 && !finalizingListOperations) return false;
        setLoading('Loading known files...');
        try {
            const result = await window.maiaApi.request('/api/file/list');
            const entries = Array.isArray(result.entries)
                ? result.entries
                : (Array.isArray(result.files) ? result.files : []);
            renderFiles(entries);
            setStatus(entries.length > 0 ? '' : 'No known files.');
            return true;
        } catch (error) {
            // Keep the existing list on screen if refreshing fails.
            setStatus(error.message || 'Unable to load known files.', true);
            return false;
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
                replaceCurrentLine(candidate);
                completionQuery = currentLine().value;
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
        const value = currentLine().value;
        const requestId = ++completionRequest;
        completionQuery = value;
        completionPending = true;
        showCompletionLoading();
        try {
            const result = await window.maiaApi.request(`/api/file/complete?path=${encodeURIComponent(value)}`);
            if (requestId !== completionRequest || currentLine().value !== value) return;
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
        const line = currentLine();
        if (candidates.length === 0 || completionQuery !== line.value) return;
        const value = candidates.length === 1 ? candidates[0] : commonPrefix(candidates);
        if (value && value !== line.value) {
            replaceCurrentLine(value);
            window.clearTimeout(completionTimer);
            void refreshCompletion();
        }
        input.focus();
    }

    input.addEventListener('input', () => {
        resizeInput();
        completionRequest++;
        candidates = [];
        completionQuery = currentLine().value;
        completionPending = true;
        showCompletionLoading();
        window.clearTimeout(completionTimer);
        completionTimer = window.setTimeout(() => void refreshCompletion(), 100);
    });

    input.addEventListener('keydown', (event) => {
        if (event.key === 'Tab' && (currentLine().value === '' || completionPending ||
            (completionQuery === currentLine().value && candidates.length > 0))) {
            event.preventDefault();
            window.clearTimeout(completionTimer);
            const value = currentLine().value;
            if (completionQuery === value && candidates.length > 0) {
                completePath();
            } else {
                void refreshCompletion().then(() => {
                    if (currentLine().value === value) completePath();
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
        let addedFileCount = 0;
        setLoading(paths.length === 1 ? `Adding ${paths[0]}...` : `Adding ${paths.length} entries...`);
        try {
            for (const path of paths) {
                const result = await window.maiaApi.request('/api/file/add', {
                    method: 'POST',
                    headers: { 'Content-Type': 'text/plain; charset=utf-8' },
                    body: path
                });
                addedFileCount += Array.isArray(result.paths) ? result.paths.length : 1;
                added++;
            }
            input.value = '';
            resizeInput();
            candidates = [];
            completion.hidden = true;
            completionPending = false;
            await loadFiles();
            setStatus(paths.length === 1 && addedFileCount === 1
                ? `Added ${paths[0]}.`
                : `Added ${addedFileCount} files.`);
        } catch (error) {
            input.value = paths.slice(added).join('\n');
            resizeInput();
            candidates = [];
            completion.hidden = true;
            completionPending = false;
            completionQuery = currentLine().value;
            await loadFiles();
            const progress = added > 0
                ? ` Added ${addedFileCount} files from ${added} of ${paths.length} entries before the error.`
                : '';
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
            completionQuery = currentLine().value;
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

    window.maiaUi.bindBusyClick(removePatternButton, async () => {
        const pattern = input.value.trim();
        if (pattern === '') {
            setStatus('Enter a pattern to remove.', true);
            input.focus();
            return;
        }
        if (/[\r\n]/.test(pattern)) {
            setStatus('Enter one pattern to remove at a time.', true);
            input.focus();
            return;
        }
        await forgetPattern(pattern);
        input.value = '';
        resizeInput();
        candidates = [];
        completion.hidden = true;
        completionPending = false;
    }, {
        busyText: 'Removing pattern...',
        onError: (error) => setStatus(error.message || 'Unable to remove pattern.', true)
    });

    window.maiaUi.bindBusyClick(root.querySelector('[data-known-files-action="remove-selected"]'), removeSelectedFiles, {
        busyText: 'Removing selected files...',
        onError: (error) => setStatus(error.message || 'Unable to remove selected files.', true)
    });

    window.maiaUi.bindBusyClick(refreshButton, loadFiles, {
        busyText: 'Refreshing known files...',
        onError: (error) => setStatus(error.message || 'Unable to refresh known files.', true)
    });

    window.maiaUi.bindBusyClick(clearButton, async () => {
        setLoading('Clearing known files...');
        await window.maiaApi.request('/api/file/clear', { method: 'POST' });
        await loadFiles();
        setStatus('Cleared the file list.');
    }, {
        busyText: 'Clearing file list...',
        onError: (error) => setStatus(error.message || 'Unable to clear the file list.', true)
    });

    void loadFiles();
})();
