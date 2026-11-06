/* Generic workspace-root-bounded path browsing, viewing, and text editing. */
(() => {
    'use strict';

    const root = document.querySelector('.path-browser');
    if (!root) return;
    const api = window.maiaApi;
    const workspace = root.dataset.workspace;
    const sessionTarget = root.dataset.sessionTarget || '';
    const initialFile = root.dataset.initialFile || '';
    const fileOnly = root.dataset.fileOnly === '1';
    let currentPath = root.dataset.relativePath || '';
    let entries = [];
    const selectedPaths = new Set();
    let viewedPath = '';
    let originalContent = '';
    let viewedContentKind = '';
    let selectedLineStart = null;
    let selectedLineEnd = null;
    let selectionAnchorStart = null;
    let selectionAnchorEnd = null;
    let selectingLines = false;
    let draggedLineSelection = false;
    let sessionTargetsLoaded = false;
    let availableSessionTargets = [];
    let sessionTargetSuggestions = [];
    let chosenSessionTarget = '';

    const role = (name) => root.querySelector(`[data-role="${name}"]`);
    const action = (name) => root.querySelector(`[data-action="${name}"]`);
    const list = role('list');
    const breadcrumb = role('breadcrumb');
    const status = role('status');
    const addSelectedButton = action('add-selected');
    const addViewedButton = action('add-viewed');
    const clearLineSelectionButton = action('clear-line-selection');
    const sessionTargetFixed = role('session-target-fixed');
    const sessionTargetControl = role('session-target-control');
    const sessionTargetInput = role('session-target');
    const sessionTargetMenu = role('session-target-menu');
    const sessionTargetStatus = role('session-target-status');
    const viewer = role('viewer');
    const viewerTitle = role('viewer-title');
    const viewerContent = role('viewer-content');
    const editor = role('editor');
    const baseUri = String(window.MAIA_BASE_PATH || '').replace(/\/$/, '');
    const filesystemLocation = document.querySelector('[data-role="filesystem-location"]');
    if (filesystemLocation) filesystemLocation.appendChild(breadcrumb);

    list.addEventListener('dragstart', (event) => {
        const link = event.target.closest('a[data-workspace-path]');
        if (!link || !event.dataTransfer) return;
        event.dataTransfer.setData('text/plain', link.dataset.workspacePath);
        event.dataTransfer.effectAllowed = 'copy';
    });

    function uriFor(path = '') {
        const safe = String(path).split('/').filter(Boolean).map(encodeURIComponent).join('/');
        const rootUri = `${baseUri}${root.dataset.uriRoot}`;
        if (safe) return `${rootUri}/${safe}`;
        return `${rootUri}${root.dataset.rootQuery || ''}`;
    }

    function setStatus(message, error = false, loading = false) {
        if (loading) window.maiaUi.setLoadingStatus(status, message);
        else window.maiaUi.setStatus(status, message, { error });
    }

    function updateBreadcrumb(filePath = '') {
        breadcrumb.replaceChildren();
        const parts = currentPath.split('/').filter(Boolean);
        const addLink = (label, path) => {
            const link = document.createElement('a');
            link.href = uriFor(path);
            link.textContent = label;
            breadcrumb.appendChild(link);
        };
        addLink('/', '');
        let path = '';
        parts.forEach((part, index) => {
            breadcrumb.appendChild(document.createTextNode(index === 0 ? ' ' : ' / '));
            path = path ? `${path}/${part}` : part;
            addLink(part, path);
        });
        if (filePath) {
            const name = filePath.split('/').pop();
            if (name) {
                breadcrumb.appendChild(document.createTextNode(parts.length === 0 ? ' ' : ' / '));
                addLink(name, filePath);
            }
        }
    }

    function selectedEntries() {
        return entries.filter((entry) => selectedPaths.has(entry.path));
    }

    function updateSelectionActions() {
        const selected = selectedEntries();
        const onlyFiles = selected.length > 0 && selected.every((entry) => entry.type === 'file');
        const copyButton = action('copy-selected');
        const moveButton = action('move-selected');
        const deleteButton = action('delete-selected');
        if (copyButton) copyButton.disabled = selected.length === 0;
        if (moveButton) moveButton.disabled = selected.length === 0;
        if (deleteButton) {
            deleteButton.disabled = !onlyFiles;
            deleteButton.title = selected.length > 0 && !onlyFiles
                ? 'Bulk delete is limited to files; deselect directories first.'
                : 'Delete selected files';
        }
        if (addSelectedButton) addSelectedButton.disabled = selected.length === 0;
    }

    async function executeWorkspaceOperation(operation, values) {
        return api.request('/api/workspace/operation', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ action: operation, ...values })
        });
    }

    async function renameEntry(entry) {
        const row = Array.from(list.children).find((candidate) => candidate.dataset.path === entry.path);
        const link = row?.querySelector('.path-browser-name');
        if (!row || !link || row.querySelector('.path-browser-rename-input')) return;

        const input = document.createElement('input');
        input.className = 'path-browser-rename-input';
        input.type = 'text';
        input.value = entry.name;
        input.setAttribute('aria-label', `New name for ${entry.name}`);
        link.replaceWith(input);
        input.focus();
        input.select();
        let finished = false;
        const restore = () => {
            if (finished) return;
            finished = true;
            input.replaceWith(link);
        };
        const save = async () => {
            if (finished) return;
            const name = input.value.trim();
            if (name === '' || name === entry.name || name.includes('/') || name === '.' || name === '..') {
                restore();
                return;
            }
            finished = true;
            input.disabled = true;
            try {
                await executeWorkspaceOperation('rename', { path: entry.path, name });
                await loadDirectory();
                setStatus(`Renamed ${entry.name} to ${name}.`);
            } catch (error) {
                input.disabled = false;
                finished = false;
                input.focus();
                input.select();
                setStatus(error.message || 'Unable to rename path.', true);
            }
        };
        input.addEventListener('keydown', (event) => {
            if (event.key === 'Enter') {
                event.preventDefault();
                void save();
            } else if (event.key === 'Escape') {
                event.preventDefault();
                restore();
            }
        });
        input.addEventListener('blur', () => {
            if (!finished) restore();
        });
    }

    async function runEntryCopyMove(entry, operation) {
        const destination = window.prompt(
            `${operation === 'copy' ? 'Copy' : 'Move'} to workspace-relative path:`,
            entry.path
        );
        if (destination === null || destination.trim() === '' || destination.trim() === entry.path) return;
        await executeWorkspaceOperation(operation, { path: entry.path, destination: destination.trim() });
        await loadDirectory();
        setStatus(`${operation === 'copy' ? 'Copied' : 'Moved'} ${entry.name}.`);
    }

    async function runEntryDelete(entry, operation) {
        const messages = {
            delete: `Delete file ${entry.name}?`,
            remove: `Remove empty directory ${entry.name}?`,
            'delete-tree': `Delete directory tree ${entry.name} and all of its contents? This cannot be undone.`
        };
        if (!window.confirm(messages[operation])) return;
        await executeWorkspaceOperation(operation, { path: entry.path });
        await loadDirectory();
        setStatus(operation === 'delete-tree' ? `Deleted directory tree ${entry.name}.` : `Deleted ${entry.name}.`);
    }

    function createEntryActionMenu(entry) {
        const items = [
            { icon: '\u270E', label: 'Rename', run: () => renameEntry(entry) },
            { icon: '\u270E', label: 'Edit', run: () => { window.location.href = `${uriFor(entry.path)}?edit=1`; } },
            { icon: '\u29C9', label: 'Copy', run: () => runEntryCopyMove(entry, 'copy') },
            { icon: '\u21AA', label: 'Move', run: () => runEntryCopyMove(entry, 'move') }
        ];
        if (entry.type === 'directory') {
            if (entry.empty === true) {
                items.push({ icon: '\u00D7', label: 'Remove', danger: true, run: () => runEntryDelete(entry, 'remove') });
            }
            items.push({ icon: '\u2612', label: 'Delete tree', danger: true, run: () => runEntryDelete(entry, 'delete-tree') });
        } else {
            items.push({ icon: '\u00D7', label: 'Delete', danger: true, run: () => runEntryDelete(entry, 'delete') });
            items.push({
                type: 'link', icon: '\u21A7', label: 'Download',
                href: api.url(`/api/workspace/operation?path=${encodeURIComponent(entry.path)}&download=1&workspace=${encodeURIComponent(workspace)}`)
            });
        }
        return window.maiaActionMenu.create({
            wrapperClassName: 'path-browser-entry-menu-wrapper',
            triggerClassName: 'path-browser-entry-menu-trigger',
            triggerIcon: '\u2630',
            ariaLabel: `Actions for ${entry.name}`,
            title: `Actions for ${entry.name}`,
            menuLabel: `Actions for ${entry.name}`,
            menuClassName: 'path-browser-entry-menu',
            floatingMenuClass: 'path-browser-entry-menu-floating',
            items,
            onError: (error) => setStatus(error.message || 'Unable to perform file action.', true)
        });
    }

    async function operateOnSelectedPaths(operation, button) {
        const selected = selectedEntries();
        if (selected.length === 0) return;
        if (operation === 'delete' && selected.some((entry) => entry.type !== 'file')) {
            setStatus('For safety, bulk delete is limited to files. Deselect directories first.', true);
            return;
        }
        if (operation === 'delete' && !window.confirm(
            `Delete ${selected.length} selected file${selected.length === 1 ? '' : 's'}?`
        )) return;

        let destination = '';
        if (operation === 'copy' || operation === 'move') {
            const answer = window.prompt(
                `${operation === 'copy' ? 'Copy' : 'Move'} selected paths to directory:`,
                currentPath
            );
            if (answer === null) return;
            destination = answer.trim().replace(/[\\/]+$/, '');
        }

        const operationLabel = operation === 'copy' ? 'Copying' : operation === 'move' ? 'Moving' : 'Deleting';
        await window.maiaUi.runBusy(button, `${operationLabel} selected paths...`, async () => {
            setStatus(`${operationLabel} ${selected.length} selected path${selected.length === 1 ? '' : 's'}...`, false, true);
            let completed = 0;
            try {
                for (const entry of selected) {
                    const values = operation === 'delete'
                        ? { path: entry.path }
                        : {
                            path: entry.path,
                            destination: `${destination ? `${destination}/` : ''}${entry.name}`
                        };
                    await executeWorkspaceOperation(operation, values);
                    completed++;
                }
                selectedPaths.clear();
                await loadDirectory();
                setStatus(`${operationLabel === 'Copying' ? 'Copied' : operationLabel === 'Moving' ? 'Moved' : 'Deleted'} ${completed} selected path${completed === 1 ? '' : 's'}.`);
            } catch (error) {
                selectedPaths.clear();
                await loadDirectory();
                setStatus(`${error.message || `Unable to ${operation} selected paths.`}${completed > 0 ? ` Completed ${completed} of ${selected.length}.` : ''}`, true);
            }
        });
        updateSelectionActions();
    }

    function renderEntries() {
        list.replaceChildren();
        for (const entry of entries) {
            const item = document.createElement('li');
            item.dataset.path = entry.path;
            const path = currentPath ? `${currentPath}/${entry.name}` : entry.name;
            const checkbox = document.createElement('input');
            checkbox.type = 'checkbox';
            checkbox.checked = selectedPaths.has(entry.path);
            checkbox.setAttribute('aria-label', `Select ${entry.name}`);
            checkbox.addEventListener('change', () => {
                if (checkbox.checked) selectedPaths.add(entry.path);
                else selectedPaths.delete(entry.path);
                updateSelectionActions();
            });
            item.appendChild(checkbox);
            item.appendChild(createEntryActionMenu(entry));

            const icon = document.createElement('a');
            icon.className = `path-browser-entry-icon${entry.type === 'directory' ? ' directory' : ' file'}`;
            icon.href = uriFor(path);
	    if (entry.type === 'file') {
		icon.draggable = true;
                icon.dataset.workspacePath = path;
	    }
            icon.textContent = entry.type === 'directory' ? '\u{1F4C1}' : '\u{1F4C4}';
            icon.title = entry.type === 'directory' ? `Open folder ${entry.name}` : `View file ${entry.name}`;
            icon.setAttribute('aria-label', entry.type === 'directory' ? `Open folder ${entry.name}` : `View file ${entry.name}`);
            item.appendChild(icon);

            const name = document.createElement('a');
            name.className = `path-browser-name${entry.type === 'directory' ? ' directory' : ''}`;
            name.href = uriFor(path);
            if (entry.type === 'file') {
                name.draggable = true;
                name.dataset.workspacePath = path;
            }
            name.textContent = entry.name;
            item.appendChild(name);

            const size = document.createElement('span');
            size.className = 'path-browser-entry-size';
            size.textContent = entry.type === 'directory' ? '' : formatSize(entry.size);
            item.appendChild(size);
            list.appendChild(item);
        }
        if (entries.length === 0) {
            const item = document.createElement('li');
            item.textContent = 'No files or directories.';
            list.appendChild(item);
        }
        updateSelectionActions();
    }

    function formatSize(value) {
        const size = Number(value);
        if (!Number.isFinite(size)) return 'File';
        if (size < 1024) return `${size} B`;
        if (size < 1024 * 1024) return `${(size / 1024).toFixed(1)} KB`;
        return `${(size / (1024 * 1024)).toFixed(1)} MB`;
    }

    function activeSessionTarget() {
        return sessionTarget || chosenSessionTarget;
    }

    function updateAddViewedButton() {
        if (!addViewedButton) return;
        const hasSelection = selectedLineStart !== null && selectedLineEnd !== null;
        const hasViewedFile = viewedContentKind !== '';
        addViewedButton.hidden = !hasViewedFile;
        addViewedButton.textContent = hasSelection ? 'Add selected' : 'Add file';
        if (clearLineSelectionButton) clearLineSelectionButton.hidden = !hasSelection;
        addViewedButton.disabled = !hasViewedFile || activeSessionTarget() === '';
    }

    function resetLineSelection() {
        selectedLineStart = null;
        selectedLineEnd = null;
        selectionAnchorStart = null;
        selectionAnchorEnd = null;
        selectingLines = false;
        draggedLineSelection = false;
    }

    function clearLineSelection() {
        resetLineSelection();
        viewerContent.querySelectorAll('.path-browser-text-line.selected, .workspace-markdown-block.selected')
            .forEach((line) => line.classList.remove('selected'));
        setStatus('');
        updateAddViewedButton();
    }

    function applyLineSelection(selector) {
        const first = Math.min(selectedLineStart, selectedLineEnd);
        const last = Math.max(selectedLineStart, selectedLineEnd);
        viewerContent.querySelectorAll(selector).forEach((node) => {
            const start = Number(node.dataset.lineStart ?? node.dataset.line);
            const end = Number(node.dataset.lineEnd ?? node.dataset.line);
            node.classList.toggle('selected', start <= last && end >= first);
        });
        setStatus(`Selected source lines: ${first}-${last}`);
        updateAddViewedButton();
    }

    function selectTextLine(lineNumber, extend = false) {
        if (extend && selectionAnchorStart !== null) {
            selectedLineStart = Math.min(selectionAnchorStart, lineNumber);
            selectedLineEnd = Math.max(selectionAnchorStart, lineNumber);
        } else {
            selectionAnchorStart = lineNumber;
            selectedLineStart = lineNumber;
            selectedLineEnd = lineNumber;
        }
        applyLineSelection('.path-browser-text-line');
    }

    function renderTextLines(content) {
        viewerContent.classList.remove('path-browser-markdown-content');
        viewerContent.classList.add('path-browser-text-content');
        const fragment = document.createDocumentFragment();
        const lines = content.split(/\r\n|\n|\r/);
        lines.forEach((line, index) => {
            const lineNumber = index + 1;
            const row = document.createElement('div');
            row.className = 'path-browser-text-line';
            row.dataset.line = String(lineNumber);
            row.tabIndex = 0;
            row.setAttribute('role', 'button');
            row.setAttribute('aria-pressed', 'false');

            const number = document.createElement('span');
            number.className = 'path-browser-line-number';
            number.textContent = String(lineNumber);
            number.setAttribute('aria-hidden', 'true');
            const text = document.createElement('span');
            text.className = 'path-browser-line-text';
            text.textContent = line;
            row.append(number, text);

            row.addEventListener('pointerdown', (event) => {
                event.preventDefault();
                selectingLines = true;
                draggedLineSelection = false;
                selectTextLine(lineNumber, event.shiftKey);
            });
            row.addEventListener('pointerenter', () => {
                if (!selectingLines) return;
                draggedLineSelection = true;
                selectTextLine(lineNumber, true);
            });
            row.addEventListener('pointerup', () => { selectingLines = false; });
            row.addEventListener('click', (event) => {
                if (!event.shiftKey && !draggedLineSelection) selectTextLine(lineNumber);
                selectingLines = false;
                draggedLineSelection = false;
            });
            row.addEventListener('keydown', (event) => {
                if (event.key !== 'Enter' && event.key !== ' ') return;
                event.preventDefault();
                selectTextLine(lineNumber, event.shiftKey);
            });
            fragment.appendChild(row);
        });
        viewerContent.replaceChildren(fragment);
    }

    function selectMarkdownBlock(block, extend = false) {
        const start = Number(block.dataset.lineStart);
        const end = Number(block.dataset.lineEnd);
        if (!Number.isInteger(start) || !Number.isInteger(end)) return;
        if (extend && selectionAnchorStart !== null) {
            selectedLineStart = Math.min(selectionAnchorStart, start);
            selectedLineEnd = Math.max(selectionAnchorEnd, end);
        } else {
            selectionAnchorStart = start;
            selectionAnchorEnd = end;
            selectedLineStart = start;
            selectedLineEnd = end;
        }
        applyLineSelection('.workspace-markdown-block');
    }

    function bindMarkdownLineSelection() {
        viewerContent.querySelectorAll('.workspace-markdown-block').forEach((block) => {
            block.addEventListener('pointerdown', (event) => {
                if (event.target.closest('a, button, input')) return;
                event.preventDefault();
                selectingLines = true;
                draggedLineSelection = false;
                selectMarkdownBlock(block, event.shiftKey);
            });
            block.addEventListener('pointerenter', () => {
                if (!selectingLines) return;
                draggedLineSelection = true;
                selectMarkdownBlock(block, true);
            });
            block.addEventListener('pointerup', () => { selectingLines = false; });
            block.addEventListener('click', (event) => {
                if (event.target.closest('a, button, input')) return;
                if (!event.shiftKey && !draggedLineSelection) selectMarkdownBlock(block);
                selectingLines = false;
                draggedLineSelection = false;
            });
            block.addEventListener('keydown', (event) => {
                if ((event.key !== 'Enter' && event.key !== ' ') || event.target.closest('a, button, input')) return;
                event.preventDefault();
                selectMarkdownBlock(block, event.shiftKey);
            });
        });
    }

    function chooseSessionTarget(name) {
        if (!availableSessionTargets.includes(name)) return;
        chosenSessionTarget = name;
        sessionTargetInput.value = name;
        sessionTargetMenu.hidden = true;
        sessionTargetInput.setAttribute('aria-expanded', 'false');
        sessionTargetStatus.textContent = '';
        try {
            window.sessionStorage.setItem(`maia-file-session-target:${workspace}`, name);
        } catch (_) {
            // Session storage can be unavailable in restricted browser contexts.
        }
        updateAddViewedButton();
    }

    function renderSessionTargetSuggestions() {
        const query = sessionTargetInput.value.trim();
        let matcher = null;
        if (query !== '') {
            try {
                matcher = new RegExp(query, 'i');
            } catch (_) {
                sessionTargetSuggestions = [];
                sessionTargetMenu.replaceChildren();
                sessionTargetMenu.hidden = true;
                sessionTargetInput.setAttribute('aria-expanded', 'false');
                sessionTargetStatus.textContent = 'Invalid session search pattern.';
                return;
            }
        }
        sessionTargetSuggestions = availableSessionTargets.filter((name) => !matcher || matcher.test(name));
        sessionTargetMenu.replaceChildren();
        for (const name of sessionTargetSuggestions) {
            const option = document.createElement('button');
            option.type = 'button';
            option.className = 'path-browser-session-option';
            option.setAttribute('role', 'option');
            option.setAttribute('aria-selected', String(name === chosenSessionTarget));
            option.textContent = name;
            option.addEventListener('pointerdown', (event) => event.preventDefault());
            option.addEventListener('click', () => chooseSessionTarget(name));
            sessionTargetMenu.appendChild(option);
        }
        sessionTargetMenu.hidden = sessionTargetSuggestions.length === 0;
        sessionTargetInput.setAttribute('aria-expanded', String(!sessionTargetMenu.hidden));
        if (query !== '' && sessionTargetSuggestions.length === 0) {
            sessionTargetStatus.textContent = 'No matching sessions.';
        } else if (sessionTargetSuggestions.length > 0 && chosenSessionTarget === '') {
            sessionTargetStatus.textContent = 'Choose a matching session.';
        } else if (chosenSessionTarget !== '') {
            sessionTargetStatus.textContent = '';
        }
    }

    function completeSessionTarget() {
        if (sessionTargetSuggestions.length === 0) return;
        if (sessionTargetSuggestions.length === 1) {
            chooseSessionTarget(sessionTargetSuggestions[0]);
            return;
        }
        const query = sessionTargetInput.value.trim();
        const prefixOnly = sessionTargetSuggestions.filter((name) => name.toLowerCase().startsWith(query.toLowerCase()));
        if (prefixOnly.length === 0) return;
        let prefix = prefixOnly[0];
        for (const name of prefixOnly.slice(1)) {
            let length = 0;
            while (length < prefix.length && length < name.length &&
                prefix[length].toLowerCase() === name[length].toLowerCase()) {
                length++;
            }
            prefix = prefix.slice(0, length);
        }
        if (prefix.length > query.length) {
            sessionTargetInput.value = prefix;
            chosenSessionTarget = availableSessionTargets.includes(prefix) ? prefix : '';
            renderSessionTargetSuggestions();
            updateAddViewedButton();
        }
    }

    async function loadSessionTargets() {
        if (sessionTarget !== '') {
            sessionTargetFixed.textContent = `Adding to session ${sessionTarget}`;
            sessionTargetFixed.hidden = false;
            sessionTargetControl.hidden = true;
            updateAddViewedButton();
            return;
        }
        sessionTargetFixed.hidden = true;
        sessionTargetControl.hidden = false;
        if (sessionTargetsLoaded) return;
        sessionTargetsLoaded = true;
        sessionTargetInput.disabled = true;
        sessionTargetStatus.textContent = 'Loading sessions...';
        try {
            const result = await api.request('/api/session/list');
            const matching = (Array.isArray(result.sessions) ? result.sessions : [])
                .filter((item) => item && typeof item.name === 'string' && item.workspace === workspace);
            availableSessionTargets = matching.map((item) => item.name);
            let stored = '';
            try {
                stored = window.sessionStorage.getItem(`maia-file-session-target:${workspace}`) || '';
            } catch (_) {
                // Session storage can be unavailable in restricted browser contexts.
            }
            const validNames = new Set(availableSessionTargets);
            chosenSessionTarget = validNames.has(stored)
                ? stored
                : (validNames.has(result.selected) ? result.selected : '');
            sessionTargetInput.value = chosenSessionTarget;
            sessionTargetInput.disabled = matching.length === 0;
            sessionTargetStatus.textContent = matching.length > 0
                ? ''
                : 'Create or configure a session for this workspace first.';
            sessionTargetMenu.hidden = true;
            sessionTargetInput.setAttribute('aria-expanded', 'false');
        } catch (error) {
            sessionTargetsLoaded = false;
            availableSessionTargets = [];
            chosenSessionTarget = '';
            sessionTargetInput.disabled = true;
            sessionTargetStatus.textContent = error.message || 'Unable to load sessions.';
        }
        updateAddViewedButton();
    }

    async function loadDirectory() {
        root.classList.remove('viewer-open');
        viewer.hidden = true;
        action('back').hidden = true;
        action('edit').hidden = true;
        if (fileOnly) {
            list.hidden = true;
            if (initialFile) {
                updateBreadcrumb(initialFile);
                await openFile(initialFile);
            } else {
                setStatus('No file was specified for this page.', true);
            }
            return;
        }
        list.hidden = false;
        selectedPaths.clear();
        updateSelectionActions();
        setStatus('Loading files...', false, true);
        try {
            const result = await api.request(`/api/workspace/files?path=${encodeURIComponent(currentPath)}`);
            entries = Array.isArray(result.entries) ? result.entries : [];
            updateBreadcrumb();
            renderEntries();
            if (initialFile) await openFile(initialFile);
            else setStatus('');
        } catch (error) {
            list.replaceChildren();
            setStatus(error.message || 'Unable to load workspace files.', true);
        }
    }

    async function openFile(path, edit = false) {
        setStatus('Loading file...', false, true);
        viewedContentKind = '';
        resetLineSelection();
        addViewedButton.hidden = true;
        updateAddViewedButton();
        try {
            const result = await api.request(`/api/workspace/operation?view=1&path=${encodeURIComponent(path)}`);
            viewedPath = path;
            viewerTitle.textContent = path.split('/').pop() || path;
            updateBreadcrumb(path);
            viewer.hidden = false;
            root.classList.add('viewer-open');
            editor.hidden = true;
            viewerContent.hidden = false;
            action('back').hidden = false;
            action('edit').hidden = result.kind === 'binary';
            action('save').hidden = true;
            action('cancel').hidden = true;
            viewerContent.replaceChildren();
            if (result.kind === 'binary') {
                viewedContentKind = 'file';
                addViewedButton.textContent = 'Add file';
                addViewedButton.hidden = false;
                void loadSessionTargets();
                const rawUrl = api.url(`/api/workspace/operation?path=${encodeURIComponent(path)}&raw=1&workspace=${encodeURIComponent(workspace)}`);
                let media;
                if (result.mime?.startsWith('image/')) {
                    media = document.createElement('img'); media.alt = viewerTitle.textContent;
                } else if (result.mime?.startsWith('audio/')) {
                    media = document.createElement('audio'); media.controls = true;
                } else if (result.mime?.startsWith('video/')) {
                    media = document.createElement('video'); media.controls = true;
                } else if (result.mime === 'application/pdf') {
                    media = document.createElement('iframe'); media.title = viewerTitle.textContent;
                }
                if (media) media.src = rawUrl;
                else {
                    media = document.createElement('a'); media.href = rawUrl; media.textContent = `Download ${viewerTitle.textContent}`;
                }
                viewerContent.appendChild(media);
            } else {
                viewedContentKind = 'lines';
                addViewedButton.textContent = 'Add file';
                addViewedButton.hidden = false;
                void loadSessionTargets();
                originalContent = String(result.content ?? '');
                if (/\.(?:md|markdown)$/i.test(path) && typeof window.maiaRenderWorkspaceMarkdown === 'function') {
                    try {
                        viewerContent.classList.remove('path-browser-text-content');
                        viewerContent.classList.add('path-browser-markdown-content');
                        viewerContent.replaceChildren(window.maiaRenderWorkspaceMarkdown(originalContent));
                        bindMarkdownLineSelection();
                    } catch (_) {
                        renderTextLines(originalContent);
                    }
                } else {
                    renderTextLines(originalContent);
                }
                if (edit) startEditing();
            }
            setStatus('');
            updateAddViewedButton();
        } catch (error) {
            viewedContentKind = '';
            addViewedButton.hidden = true;
            updateAddViewedButton();
            viewer.hidden = true;
            root.classList.remove('viewer-open');
            setStatus(error.message || 'Unable to view file.', true);
        }
    }

    async function addSelectedFiles() {
        if (!sessionTarget || selectedPaths.size === 0) return;
        await window.maiaUi.runBusy(addSelectedButton, 'Adding files to session...', async () => {
            setStatus('Adding files to session...', false, true);
            try {
                for (const path of selectedPaths) {
                    await api.request('/api/file/add', {
                        method: 'POST',
                        headers: { 'Content-Type': 'text/plain; charset=utf-8' },
                        body: path
                    });
                }
                selectedPaths.clear();
                await loadDirectory();
                setStatus('Files added to session.');
            } catch (error) {
                setStatus(error.message || 'Unable to add files to session.', true);
            } finally {
                if (addSelectedButton) addSelectedButton.disabled = selectedPaths.size === 0;
            }
        });
    }

    async function addViewedContent() {
        const target = activeSessionTarget();
        if (target === '' || viewedPath === '') return;

        let payload = '';
        let description = '';
        if (viewedContentKind === 'file' || viewedContentKind === 'lines' &&
            (selectedLineStart === null || selectedLineEnd === null)) {
            payload = viewedPath;
            description = `file ${viewedPath}`;
        } else if (viewedContentKind === 'lines' && selectedLineStart !== null && selectedLineEnd !== null) {
            const first = Math.min(selectedLineStart, selectedLineEnd);
            const last = Math.max(selectedLineStart, selectedLineEnd);
            payload = `${viewedPath}:${first}-${last}`;
            description = `lines ${first}-${last} from ${viewedPath}`;
        } else {
            return;
        }

        await window.maiaUi.runBusy(addViewedButton, 'Adding to session...', async () => {
            setStatus(`Adding ${description} to session ${target}...`, false, true);
            try {
                await api.request('/api/file/add', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'text/plain; charset=utf-8',
                        'X-MAIA-Session': target
                    },
                    body: payload
                });
                if (viewedContentKind === 'lines') {
                    resetLineSelection();
                    viewerContent.querySelectorAll('.path-browser-text-line.selected, .workspace-markdown-block.selected')
                        .forEach((line) => line.classList.remove('selected'));
                }
                setStatus(`Added ${description} to session ${target}.`);
            } catch (error) {
                setStatus(error.message || 'Unable to add viewed content to the session.', true);
            }
        });
        updateAddViewedButton();
    }

    function startEditing() {
        viewedContentKind = '';
        resetLineSelection();
        updateAddViewedButton();
        editor.value = originalContent;
        editor.hidden = false;
        viewerContent.hidden = true;
        action('edit').hidden = true;
        action('save').hidden = false;
        action('cancel').hidden = false;
        editor.focus();
    }

    async function saveFile() {
        await window.maiaUi.runBusy(action('save'), 'Saving file...', async () => {
            setStatus('Saving file...', false, true);
            await api.request('/api/workspace/operation', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ action: 'write', path: viewedPath, content: editor.value })
            });
            originalContent = editor.value;
            await openFile(viewedPath);
            setStatus('Saved.');
        });
    }

    async function createPath(isDirectory) {
        const name = window.prompt(isDirectory ? 'Folder name:' : 'File name:');
        if (!name) return;
        const path = currentPath ? `${currentPath}/${name}` : name;
        try {
            await api.request('/api/workspace/operation', {
                method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ action: isDirectory ? 'mkdir' : 'create', path })
            });
            await loadDirectory();
        } catch (error) { setStatus(error.message || 'Unable to create path.', true); }
    }

    async function uploadFiles(files) {
        const fileArray = Array.from(files || []);
        for (const file of fileArray) {
            const form = new FormData();
            form.append('file', file);
            form.append('path', currentPath);
            try {
                await api.request('/api/workspace/upload', { method: 'POST', body: form });
            } catch (error) { setStatus(error.message || `Unable to upload ${file.name}.`, true); return; }
        }
        await loadDirectory();
    }

    addSelectedButton?.addEventListener('click', addSelectedFiles);
    action('copy-selected')?.addEventListener('click', () => operateOnSelectedPaths('copy', action('copy-selected')));
    action('move-selected')?.addEventListener('click', () => operateOnSelectedPaths('move', action('move-selected')));
    action('delete-selected')?.addEventListener('click', () => operateOnSelectedPaths('delete', action('delete-selected')));
    addViewedButton?.addEventListener('click', addViewedContent);
    clearLineSelectionButton?.addEventListener('click', clearLineSelection);
    sessionTargetInput?.addEventListener('input', () => {
        const value = sessionTargetInput.value.trim();
        chosenSessionTarget = availableSessionTargets.includes(value) ? value : '';
        renderSessionTargetSuggestions();
        if (chosenSessionTarget !== '') {
            try {
                window.sessionStorage.setItem(`maia-file-session-target:${workspace}`, chosenSessionTarget);
            } catch (_) {
                // Ignore unavailable session storage.
            }
        }
        updateAddViewedButton();
    });
    sessionTargetInput?.addEventListener('focus', renderSessionTargetSuggestions);
    sessionTargetInput?.addEventListener('click', renderSessionTargetSuggestions);
    sessionTargetInput?.addEventListener('keydown', (event) => {
        if (event.key === 'ArrowDown') {
            if (sessionTargetMenu.hidden) renderSessionTargetSuggestions();
            const first = sessionTargetMenu.querySelector('button');
            if (first) {
                event.preventDefault();
                first.focus();
            }
        } else if (event.key === 'Enter' && !sessionTargetMenu.hidden) {
            const option = sessionTargetMenu.contains(document.activeElement)
                ? document.activeElement
                : sessionTargetMenu.querySelector('button');
            if (option) {
                event.preventDefault();
                option.click();
            }
        } else if (event.key === 'Tab' && sessionTargetSuggestions.length === 1) {
            event.preventDefault();
            chooseSessionTarget(sessionTargetSuggestions[0]);
        } else if (event.key === 'Escape') {
            sessionTargetMenu.hidden = true;
            sessionTargetInput.setAttribute('aria-expanded', 'false');
        }
    });
    sessionTargetInput?.addEventListener('blur', () => {
        window.setTimeout(() => {
            if (sessionTargetMenu.contains(document.activeElement)) return;
            sessionTargetMenu.hidden = true;
            sessionTargetInput.setAttribute('aria-expanded', 'false');
        }, 100);
    });
    action('up').addEventListener('click', () => {
        const parentPath = currentPath.split('/').filter(Boolean).slice(0, -1).join('/');
        window.location.assign(uriFor(parentPath));
    });
    action('refresh').addEventListener('click', () => {
        if (!viewer.hidden && viewedPath !== '') openFile(viewedPath);
        else loadDirectory();
    });
    action('new-directory').addEventListener('click', () => createPath(true));
    action('new-file').addEventListener('click', () => createPath(false));
    action('upload').addEventListener('click', () => role('upload-input').click());
    role('upload-input').addEventListener('change', async (event) => {
        await uploadFiles(event.target.files);
        event.target.value = '';
    });
    action('edit').addEventListener('click', startEditing);
    action('save').addEventListener('click', saveFile);
    action('cancel').addEventListener('click', () => openFile(viewedPath));
    action('back').addEventListener('click', () => window.location.assign(uriFor(currentPath)));
    loadDirectory();
})();
