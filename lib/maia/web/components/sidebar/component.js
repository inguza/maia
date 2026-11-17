/* Navigation behavior owned by SidebarComponent. */
(() => {
    'use strict';

    const byId = (id) => document.getElementById(id);
    const api = (...args) => window.maiaApi.request(...args);
    const url = (path) => window.maiaApi.url(path);
    const data = { sessions: [], groups: [], workspaces: [], currentSession: '', currentWorkspace: '' };
    const expandedGroups = new Map();
    const expandedSearchGroups = new Set();
    const pendingOperations = new Set();
    const pendingSessionOperations = new Map();
    const pendingGroupOperations = new Map();

    function setError(message) {
        let element = byId('home-error') || byId('sidebar-error');
        if (!element) {
            const sidebar = byId('sidebar');
            if (!sidebar) return;
            element = document.createElement('p');
            element.id = 'sidebar-error';
            element.className = 'sidebar-placeholder';
            element.setAttribute('role', 'alert');
            sidebar.prepend(element);
        }
        element.textContent = message;
        element.hidden = !message;
    }

    function setBusy(button, message) {
        if (!button || button.dataset.busy === '1') return;
        button.dataset.busy = '1';
        button.dataset.oldText = button.textContent;
        button.disabled = true;
        button.replaceChildren();
        const spinner = document.createElement('span');
        spinner.className = 'spinner';
        spinner.setAttribute('aria-hidden', 'true');
        const label = document.createElement('span');
        label.className = 'visually-hidden';
        label.textContent = message;
        button.append(spinner, label);
    }

    function clearBusy(button) {
        if (!button || button.dataset.busy !== '1') return;
        button.textContent = button.dataset.oldText || '';
        delete button.dataset.oldText;
        delete button.dataset.busy;
        button.disabled = false;
    }

    function makeButton(label, title, handler) {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'sidebar-action';
        button.textContent = label;
        button.title = title;
        button.setAttribute('aria-label', title);
        button.addEventListener('click', handler);
        return button;
    }

    const actionMenuContexts = new WeakMap();

    function closeActionMenu(menu) {
        menu.hidden = true;
        menu.classList.remove('sidebar-item-menu-floating');
        for (const property of ['top', 'left', 'right', 'bottom', 'max-width', 'max-height']) {
            menu.style.removeProperty(property);
        }
        const context = actionMenuContexts.get(menu);
        if (context) {
            context.parent.appendChild(menu);
            context.toggle.setAttribute('aria-expanded', 'false');
        }
    }

    function closeAllActionMenus(except = null) {
        document.querySelectorAll('.sidebar-item-menu').forEach((menu) => {
            if (menu !== except) closeActionMenu(menu);
        });
    }

    function positionActionMenu(menu, toggle) {
        const margin = 8;
        const gap = 6;
        const viewportWidth = document.documentElement.clientWidth || window.innerWidth;
        const viewportHeight = document.documentElement.clientHeight || window.innerHeight;
        const anchor = toggle.getBoundingClientRect();
        menu.style.top = '0px';
        menu.style.left = '0px';
        menu.style.maxWidth = `${Math.max(1, viewportWidth - 2 * margin)}px`;
        menu.style.maxHeight = `${Math.max(1, viewportHeight - 2 * margin)}px`;
        const desiredHeight = menu.scrollHeight;
        const spaceAbove = Math.max(0, anchor.top - margin - gap);
        const spaceBelow = Math.max(0, viewportHeight - anchor.bottom - margin - gap);
        const placeAbove = desiredHeight <= spaceAbove || spaceAbove > spaceBelow;
        const height = menu.getBoundingClientRect().height;
        const top = placeAbove ? anchor.top - gap - height : anchor.bottom + gap;
        menu.style.top = `${Math.max(margin, Math.min(top, viewportHeight - margin - height))}px`;
        const width = Math.min(menu.getBoundingClientRect().width, viewportWidth - 2 * margin);
        menu.style.left = `${Math.max(margin, Math.min(anchor.right - width, viewportWidth - margin - width))}px`;
    }

    function createActionMenu(name, actions) {
        return window.maiaActionMenu.create({
            wrapperClassName: 'sidebar-item-actions',
            triggerClassName: 'sidebar-item-actions-toggle',
            triggerIcon: '\u2630',
            ariaLabel: `Actions for ${name}`,
            title: `Actions for ${name}`,
            menuLabel: `Actions for ${name}`,
            menuClassName: 'sidebar-item-menu',
            itemClassName: 'sidebar-action',
            floatingMenuClass: 'sidebar-item-menu-floating',
            items: actions.map((action) => ({
                ...action,
                busyText: `${action.label}...`
            })),
            onError: (error) => setError(error.message)
        });
    }

    function resizeSessionListToFit() {
        const list = byId('session-list');
        const sidebar = byId('sidebar');
        if (!list || !sidebar) return;
        const rows = Array.from(list.children);
        if (rows.length === 0) {
            list.style.maxHeight = 'none';
            return;
        }
        const fallbackRowHeight = 2.5 * 16;
        const heights = rows.map((row) => Math.max(row.getBoundingClientRect().height, fallbackRowHeight));
        const minimum = heights.slice(0, Math.min(3, heights.length)).reduce((sum, value) => sum + value, 0);
        const maximum = heights.slice(0, Math.min(16, heights.length)).reduce((sum, value) => sum + value, 0);
        const current = list.getBoundingClientRect().height;
        const remaining = sidebar.clientHeight - Math.max(0, sidebar.scrollHeight - current);
        list.style.maxHeight = `${Math.max(minimum, Math.min(maximum, remaining))}px`;
    }

    function validName(name) {
        return /^[A-Za-z0-9_.%+\-]+$/.test(name);
    }

    function scrollCurrentIntoView(list) {
        const item = list.querySelector('.sidebar-current-item');
        if (!item) return;

        const scrollToItem = (container) => {
            const containerRect = container.getBoundingClientRect();
            const itemRect = item.getBoundingClientRect();
            if (itemRect.top < containerRect.top) {
                container.scrollTop -= containerRect.top - itemRect.top;
            } else if (itemRect.bottom > containerRect.bottom) {
                container.scrollTop += itemRect.bottom - containerRect.bottom;
            }
        };

        scrollToItem(list);
        const sidebar = byId('sidebar');
        if (sidebar && sidebar !== list) scrollToItem(sidebar);
    }

    function renderNames(type, scrollToCurrent = false) {
        if (type === 'session') {
            renderSessionGroups(scrollToCurrent);
            return;
        }
        const list = byId(`${type}-list`);
        const placeholder = byId(`${type}-list-placeholder`);
        const input = byId(`${type}-search-input`);
        if (!list || !placeholder) return;

        const query = input?.value.trim() || '';
        const names = data[`${type}s`] || [];
        let matches = names;
        let invalidRegex = false;
        if (query) {
            try {
                const expression = new RegExp(query, 'i');
                matches = names.filter((name) => expression.test(name));
            } catch (_) {
                matches = [];
                invalidRegex = true;
            }
        }

        list.replaceChildren();
        for (const name of matches) {
            const item = document.createElement('li');
            const link = document.createElement('a');
            link.textContent = name;
            if (type === 'session') {
                link.href = url(`/session/${encodeURIComponent(name)}`);
            } else {
                link.href = url(`/${type}/${encodeURIComponent(name)}`);
            }
            item.appendChild(link);
            const isCurrent = type === 'session'
                ? name === data.currentSession
                : name === data.currentWorkspace;
            if (isCurrent) {
                item.classList.add('sidebar-current-item');
                link.setAttribute('aria-current', 'page');
            }

            if (type === 'session') {
                item.appendChild(createActionMenu(name, [
                    { icon: '\u2699\uFE0E', label: 'Settings', run: () => openSessionSettings(name) },
                    { icon: '\u270E', label: 'Rename', run: () => renameSession(name) },
                    { icon: '\u29C9', label: 'Copy', run: () => copySession(name) },
                    { icon: '\u21C4', label: 'Move', run: () => openSessionMoveDialog(name) },
                    { icon: '\u00D7', label: 'Delete', run: () => deleteSession(name) }
                ]));
            } else {
                item.appendChild(createActionMenu(name, [
                    { icon: '\u2699\uFE0E', label: 'Settings', run: () => editWorkspace(name) },
                    { icon: '\u00D7', label: 'Delete', run: () => deleteResource(type, name) }
                ]));
            }
            list.appendChild(item);
        }

        if (type === 'session') resizeSessionListToFit();
        if (scrollToCurrent) scrollCurrentIntoView(list);
        placeholder.hidden = matches.length > 0;
        if (!matches.length) {
            placeholder.textContent = invalidRegex
                ? 'Invalid regular expression.'
                : query ? 'No matches.' : `No ${type}s found.`;
        }
        updateCreateButton(type, query, names);
    }

    function treeLabel(name) {
        const value = String(name);
        const parts = value.split('%');
        return parts.every(Boolean) ? parts[parts.length - 1] : value;
    }

    function buildNameTree(names, records = new Map()) {
        const roots = [];
        const nodes = new Map();
        for (const name of names) {
            const parts = String(name).split('%');
            if (parts.some((part) => !part)) {
                const node = { name: String(name), record: records.get(String(name)) || null, children: [] };
                roots.push(node);
                nodes.set(node.name, node);
                continue;
            }
            let parent = null;
            let prefix = '';
            for (const part of parts) {
                prefix = prefix ? `${prefix}%${part}` : part;
                let node = nodes.get(prefix);
                if (!node) {
                    node = { name: prefix, record: records.get(prefix) || null, children: [] };
                    nodes.set(prefix, node);
                    if (parent) parent.children.push(node);
                    else roots.push(node);
                } else {
                    if (!node.record) node.record = records.get(prefix) || null;
                    if (parent && !parent.children.includes(node)) parent.children.push(node);
                }
                parent = node;
            }
        }
        const sortNodes = (items) => {
            items.sort((a, b) => a.name.localeCompare(b.name));
            for (const item of items) sortNodes(item.children);
        };
        sortNodes(roots);
        return roots;
    }

    function createSessionRow(name, displayName = name) {
        const row = document.createElement('div');
        row.className = 'sidebar-session-row';
        const pendingOperation = pendingSessionOperations.get(name);
        if (pendingOperation?.action === 'Deleting') {
            row.classList.add('sidebar-session-deleting');
            const spinner = document.createElement('span');
            spinner.className = 'spinner';
            spinner.setAttribute('role', 'status');
            spinner.setAttribute('aria-label', `Deleting ${name}`);
            spinner.title = `Deleting ${name}`;
            row.appendChild(spinner);
            return row;
        }

        row.draggable = true;
        row.addEventListener('dragstart', (event) => {
            event.dataTransfer?.setData('text/plain', name);
            if (event.dataTransfer) event.dataTransfer.effectAllowed = 'move';
        });
        const link = document.createElement('a');
        link.textContent = displayName;
        link.href = url(`/session/${encodeURIComponent(name)}`);
        row.appendChild(link);
        if (pendingOperation) {
            const spinner = document.createElement('span');
            spinner.className = 'spinner sidebar-session-move-spinner';
            spinner.setAttribute('role', 'status');
            spinner.setAttribute('aria-label', `${pendingOperation.action} ${name}`);
            spinner.title = `${pendingOperation.action} ${name}`;
            link.appendChild(spinner);
        }
        if (name === data.currentSession) {
            row.classList.add('sidebar-current-item');
            link.setAttribute('aria-current', 'page');
        }
        row.appendChild(createActionMenu(name, [
            { icon: '\u2699\uFE0E', label: 'Settings', run: () => openSessionSettings(name) },
            { icon: '\u270E', label: 'Rename', run: () => renameSession(name) },
            { icon: '\u29C9', label: 'Copy', run: () => copySession(name) },
            { icon: '\u21C4', label: 'Move', run: () => openSessionMoveDialog(name) },
            { icon: '\u00D7', label: 'Delete', run: () => deleteSession(name) }
        ]));
        return row;
    }

    function createSessionItem(name, children = []) {
        const item = document.createElement('li');
        item.dataset.session = name;
        if (!children.length) {
            item.appendChild(createSessionRow(name, treeLabel(name)));
            return item;
        }

        const details = document.createElement('details');
        details.className = 'sidebar-session-tree-node';
        details.open = Boolean(expandedGroups.get(`session:${name}`));
        details.addEventListener('toggle', () => expandedGroups.set(`session:${name}`, details.open));
        const summary = document.createElement('summary');
        summary.className = 'sidebar-session-tree-summary';
        summary.appendChild(createSessionRow(name, treeLabel(name)));
        details.appendChild(summary);
        details.appendChild(createSessionTree(children));
        item.appendChild(details);
        return item;
    }

    function createSessionTree(nodes, options = {}) {
        const { expression = null, showAll = false, invalidRegex = false } = options;
        const list = document.createElement('ul');
        list.className = 'sidebar-list sidebar-session-tree';
        for (const node of nodes) {
            const real = Boolean(node.record);
            const selfMatches = Boolean(expression && expression.test(node.name));
            const includeSelf = real && (showAll || (!invalidRegex && (!expression || selfMatches)));
            const childList = createSessionTree(node.children, options);
            const hasChildren = childList.children.length > 0;
            if (!includeSelf && !hasChildren) continue;

            const item = document.createElement('li');
            item.className = 'sidebar-session-tree-item';
            item.dataset.session = node.name;
            if (hasChildren) {
                const details = document.createElement('details');
                details.className = 'sidebar-session-tree-node';
                details.open = Boolean(expandedGroups.get(`session:${node.name}`));
                details.addEventListener('toggle', () => expandedGroups.set(`session:${node.name}`, details.open));
                const summary = document.createElement('summary');
                summary.className = 'sidebar-session-tree-summary';
                if (includeSelf) summary.appendChild(createSessionRow(node.name, treeLabel(node.name)));
                else {
                    const label = document.createElement('span');
                    label.className = 'sidebar-session-virtual-name';
                    label.textContent = treeLabel(node.name);
                    summary.appendChild(label);
                }
                details.appendChild(summary);
                details.appendChild(childList);
                item.appendChild(details);
            } else if (includeSelf) {
                item.appendChild(createSessionRow(node.name, treeLabel(node.name)));
            }
            list.appendChild(item);
        }
        return list;
    }

    function renderSessionGroups(scrollToCurrent = false) {
        const list = byId('session-list');
        const placeholder = byId('session-list-placeholder');
        const input = byId('session-search-input');
        if (!list || !placeholder) return;

        const query = input?.value.trim() || '';
        let expression = null;
        let invalidRegex = false;
        if (query) {
            try { expression = new RegExp(query, 'i'); }
            catch (_) { invalidRegex = true; }
        }
        const sessions = data.sessions || [];
        const groupRecords = new Map((data.groups || []).map((group) => [String(group.name), group]));
        const groupTree = buildNameTree(Array.from(groupRecords.keys()), groupRecords);
        const memberships = new Set();
        for (const group of data.groups || []) {
            for (const name of group.sessions || []) memberships.add(name);
        }

        list.replaceChildren();
        let hasVisibleSection = false;
        const makeSessionTree = (names, showAll = false) => {
            const available = names.filter((name) => sessions.includes(name));
            const records = new Map(available.map((name) => [name, true]));
            return createSessionTree(buildNameTree(available, records), { expression, showAll, invalidRegex });
        };

        const renderGroupNode = (node, inheritedShowAll = false) => {
            const name = node.name;
            const group = node.record;
            const groupMatches = Boolean(expression && !invalidRegex && expression.test(name));
            const showAllForSearch = Boolean(query && (inheritedShowAll ||
                (groupMatches && expandedSearchGroups.has(name))));
            const members = group
                ? sessions.filter((session) => (group.sessions || []).includes(session))
                : [];
            const memberTree = makeSessionTree(members, showAllForSearch);
            const childSections = node.children.map((child) => renderGroupNode(child, showAllForSearch)).filter(Boolean);
            const visible = !query || groupMatches || memberTree.children.length > 0 || childSections.length > 0;
            if (!visible) return null;

            const section = document.createElement('details');
            section.className = group ? 'sidebar-session-group' : 'sidebar-session-group sidebar-virtual-group';
            if (group) section.dataset.group = name;
            section.open = query ? true : Boolean(expandedGroups.get(`group:${name}`));
            section.addEventListener('toggle', () => {
                if (!query) expandedGroups.set(`group:${name}`, section.open);
            });

            const summary = document.createElement('summary');
            if (group) {
                const onDragOver = (event) => {
                    event.preventDefault();
                    event.stopPropagation();
                    section.classList.add('sidebar-group-drop-target');
                };
                summary.addEventListener('dragover', onDragOver);
                summary.addEventListener('dragleave', (event) => {
                    event.stopPropagation();
                    if (!summary.contains(event.relatedTarget)) section.classList.remove('sidebar-group-drop-target');
                });
                summary.addEventListener('drop', (event) => {
                    event.preventDefault();
                    event.stopPropagation();
                    section.classList.remove('sidebar-group-drop-target');
                    const session = event.dataTransfer?.getData('text/plain') || '';
                    if (session) moveSession(session, name);
                });
            }
            const label = document.createElement('span');
            label.className = 'sidebar-group-name';
            label.textContent = treeLabel(name);
            summary.appendChild(label);
            const createChild = document.createElement('button');
            createChild.type = 'button';
            createChild.className = 'sidebar-small-button sidebar-group-create-child';
            createChild.textContent = '+';
            createChild.title = `Create a group under ${name}`;
            createChild.setAttribute('aria-label', `Create a group under ${name}`);
            createChild.addEventListener('click', (event) => {
                event.preventDefault();
                event.stopPropagation();
                createSessionGroup(name);
            });
            summary.appendChild(createChild);
            if (group && pendingGroupOperations.has(name)) {
                const spinner = document.createElement('span');
                spinner.className = 'spinner sidebar-session-move-spinner';
                spinner.setAttribute('role', 'status');
                spinner.setAttribute('aria-label', `Creating group ${name}`);
                spinner.title = `Creating group ${name}`;
                summary.appendChild(spinner);
            }
            if (query && groupMatches) {
                const showAll = document.createElement('button');
                showAll.type = 'button';
                showAll.className = 'sidebar-group-show-all';
                showAll.textContent = showAllForSearch ? 'Show matches' : 'Show all';
                showAll.setAttribute('aria-label', showAllForSearch
                    ? `Show matching contents of ${name}`
                    : `Show all contents of ${name}`);
                showAll.addEventListener('click', (event) => {
                    event.preventDefault();
                    event.stopPropagation();
                    if (expandedSearchGroups.has(name)) expandedSearchGroups.delete(name);
                    else expandedSearchGroups.add(name);
                    renderSessionGroups(false);
                });
                summary.appendChild(showAll);
            }
            if (group) {
                const remove = document.createElement('button');
                remove.type = 'button';
                remove.className = 'sidebar-group-remove';
                remove.textContent = '×';
                remove.title = `Remove group ${name}`;
                remove.setAttribute('aria-label', `Remove group ${name}`);
                remove.addEventListener('click', async (event) => {
                    event.preventDefault();
                    event.stopPropagation();
                    await deleteGroup(name);
                });
                summary.appendChild(remove);
            }
            section.appendChild(summary);
            if (memberTree.children.length) section.appendChild(memberTree);
            if (childSections.length) {
                const children = document.createElement('div');
                children.className = 'sidebar-subgroups';
                for (const child of childSections) children.appendChild(child);
                section.appendChild(children);
            }
            hasVisibleSection = true;
            return section;
        };

        for (const node of groupTree) {
            const section = renderGroupNode(node);
            if (section) list.appendChild(section);
        }

        const ungrouped = sessions.filter((session) => !memberships.has(session));
        const ungroupedMatches = Boolean(expression && !invalidRegex && expression.test('Other'));
        const showAllUngrouped = Boolean(query && ungroupedMatches && expandedSearchGroups.has('Ungrouped'));
        const ungroupedTree = makeSessionTree(ungrouped, showAllUngrouped);
        if (!query || ungroupedMatches || ungroupedTree.children.length) {
            hasVisibleSection = true;
            const section = document.createElement('details');
            section.className = 'sidebar-session-group sidebar-ungrouped-group';
            section.open = query ? true : Boolean(expandedGroups.get('Ungrouped'));
            section.addEventListener('toggle', () => {
                if (!query) expandedGroups.set('Ungrouped', section.open);
            });
            const summary = document.createElement('summary');
            summary.addEventListener('dragover', (event) => {
                event.preventDefault();
                event.stopPropagation();
                section.classList.add('sidebar-group-drop-target');
            });
            summary.addEventListener('dragleave', (event) => {
                event.stopPropagation();
                if (!summary.contains(event.relatedTarget)) section.classList.remove('sidebar-group-drop-target');
            });
            summary.addEventListener('drop', (event) => {
                event.preventDefault();
                event.stopPropagation();
                section.classList.remove('sidebar-group-drop-target');
                const session = event.dataTransfer?.getData('text/plain') || '';
                if (session) moveSession(session, '');
            });
            const label = document.createElement('span');
            label.className = 'sidebar-group-name';
            label.textContent = 'Other';
            summary.appendChild(label);
            if (query && ungroupedMatches) {
                const showAll = document.createElement('button');
                showAll.type = 'button';
                showAll.className = 'sidebar-group-show-all';
                showAll.textContent = showAllUngrouped ? 'Show matches' : 'Show all';
                showAll.setAttribute('aria-label', showAllUngrouped
                    ? 'Show matching ungrouped sessions'
                    : 'Show all ungrouped sessions');
                showAll.addEventListener('click', (event) => {
                    event.preventDefault();
                    event.stopPropagation();
                    if (showAllUngrouped) expandedSearchGroups.delete('Ungrouped');
                    else expandedSearchGroups.add('Ungrouped');
                    renderSessionGroups(false);
                });
                summary.appendChild(showAll);
            }
            section.appendChild(summary);
            if (ungroupedTree.children.length) section.appendChild(ungroupedTree);
            list.appendChild(section);
        }

        if (scrollToCurrent) scrollCurrentIntoView(list);
        placeholder.hidden = hasVisibleSection;
        if (!hasVisibleSection) {
            placeholder.textContent = invalidRegex
                ? 'Invalid regular expression.'
                : query ? 'No matches.' : 'No sessions found.';
        }
        updateCreateButton('session', query, sessions);
    }

    async function createSessionGroup(parentName = '') {
        const dialog = byId('sidebar-session-group-create-dialog');
        const inputElement = byId('sidebar-session-group-create-name');
        let input;
        if (dialog && inputElement && typeof dialog.showModal === 'function') {
            byId('sidebar-session-group-create-title').textContent = parentName ? 'Create item' : 'Create group';
            byId('sidebar-session-group-create-message').textContent = parentName
                ? `This will create an item under '${parentName}'. Leave blank to create a group named '${parentName}' (unless it already exists).`
                : 'Create a top-level session group.';
            byId('sidebar-session-group-create-label').firstChild.textContent = parentName ? 'Item name' : 'Group name';
            inputElement.value = '';
            dialog.returnValue = '';
            input = await new Promise((resolve) => {
                dialog.addEventListener('close', () => {
                    resolve(dialog.returnValue === 'create' ? inputElement.value.trim() : null);
                }, { once: true });
                dialog.showModal();
                inputElement.focus();
            });
        } else {
            const promptText = parentName
                ? `This will create an item under '${parentName}'. Leave blank to create a group named '${parentName}' (unless it already exists).\nName for the new item:`
                : 'Name for the new session group:';
            input = window.prompt(promptText);
        }
        if (input === null) return;
        const childName = input.trim();
        if (!parentName && !childName) return;
        const groupName = parentName
            ? (childName ? `${parentName}%${childName}` : parentName)
            : childName;
        if (!validName(groupName)) { setError('Invalid group name.'); return; }
        if ((data.groups || []).some((group) => group.name === groupName)) {
            if (parentName && !childName) return;
            setError(`Group '${groupName}' already exists.`);
            return;
        }

        const operation = { action: 'Creating' };
        pendingGroupOperations.set(groupName, operation);
        pendingOperations.add(operation);
        data.groups.push({ name: groupName, sessions: [] });
        if (parentName) {
            const parts = parentName.split('%');
            let prefix = '';
            for (const part of parts) {
                prefix = prefix ? `${prefix}%${part}` : part;
                expandedGroups.set(`group:${prefix}`, true);
            }
        }
        renderSessionGroups(false);
        try {
            await api('/api/session/groups', {
                method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ action: 'create', name: groupName })
            });
        } catch (error) {
            data.groups = data.groups.filter((group) => group.name !== groupName);
            setError(error.message);
        } finally {
            if (pendingGroupOperations.get(groupName) === operation) {
                pendingGroupOperations.delete(groupName);
            }
            pendingOperations.delete(operation);
            if (pendingOperations.size === 0) {
                clearCompletedSessionDeletions();
                await loadSidebar(false);
            } else renderSessionGroups(false);
        }
    }

    async function confirmSidebarAction(title, message, action = 'Remove', style = 'action-check') {
        const dialog = byId('sidebar-confirm-dialog');
        const button = byId('sidebar-confirm-action');
        if (!dialog || !button || typeof dialog.showModal !== 'function') {
            return window.confirm(`${title}\n${message}`);
        }
        byId('sidebar-confirm-title').textContent = title;
        byId('sidebar-confirm-message').textContent = message;
        button.textContent = action;
        window.maiaUi.setActionType(button, style);
        dialog.returnValue = '';
        return new Promise((resolve) => {
            dialog.addEventListener('close', () => resolve(dialog.returnValue === 'confirm'), { once: true });
            dialog.showModal();
        });
    }

    async function deleteGroup(name) {
        if (!await confirmSidebarAction('Remove group', `Remove group '${name}'? Its sessions will be moved to Other.`, 'Remove', 'action-check')) return;
        try {
            await api('/api/session/groups', {
                method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ action: 'delete', name })
            });
            expandedGroups.delete(name);
            await loadSidebar();
        } catch (error) { setError(error.message); }
    }

    function beginSessionOperation(name, action) {
        if (pendingSessionOperations.has(name)) return null;
        const operation = { action };
        pendingSessionOperations.set(name, operation);
        pendingOperations.add(operation);
        renderSessionGroups(false);
        return operation;
    }

    function clearCompletedSessionDeletions() {
        for (const [name, operation] of pendingSessionOperations) {
            if (operation.completed) pendingSessionOperations.delete(name);
        }
    }

    async function finishSessionOperation(name, operation) {
        if (!operation.completed && pendingSessionOperations.get(name) === operation) {
            pendingSessionOperations.delete(name);
        }
        pendingOperations.delete(operation);
        if (pendingOperations.size === 0) {
            clearCompletedSessionDeletions();
            // Refresh once all pending operations settle, without scrolling to the current session.
            await loadSidebar(false);
        } else {
            renderSessionGroups(false);
        }
    }

    async function moveSession(name, group = '') {
        const operation = beginSessionOperation(name, 'Moving');
        if (!operation) return;

        const previousGroups = (data.groups || [])
            .filter((item) => (item.sessions || []).includes(name))
            .map((item) => item.name);

        // Update the visible membership immediately while the server operation runs.
        for (const item of data.groups || []) {
            item.sessions = (item.sessions || []).filter((session) => session !== name);
        }
        if (group) {
            const destination = (data.groups || []).find((item) => item.name === group);
            if (destination) {
                destination.sessions.push(name);
                expandedGroups.set(group, true);
            }
        } else {
            expandedGroups.set('Ungrouped', true);
        }
        renderSessionGroups(false);

        try {
            await api('/api/session/groups', {
                method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ action: 'move', session: name, group })
            });
        } catch (error) {
            for (const item of data.groups || []) {
                item.sessions = (item.sessions || []).filter((session) => session !== name);
            }
            for (const previousGroup of previousGroups) {
                const item = (data.groups || []).find((entry) => entry.name === previousGroup);
                if (item) item.sessions.push(name);
            }
            setError(error.message);
        } finally {
            await finishSessionOperation(name, operation);
        }
    }

    function openSessionMoveDialog(name) {
        const dialog = byId('sidebar-session-move-dialog');
        const select = byId('sidebar-session-move-group');
        if (!dialog || !select || typeof dialog.showModal !== 'function') {
            const options = ['(Other)', ...(data.groups || []).map((group) => group.name)];
            const choice = window.prompt(`Move '${name}' to a group (enter a group name, or leave blank for Other):\n${options.join('\n')}`);
            if (choice !== null) moveSession(name, choice.trim() === '(Other)' ? '' : choice.trim());
            return;
        }
        dialog.dataset.session = name;
        byId('sidebar-session-move-title').textContent = 'Move';
        select.replaceChildren();
        const ungrouped = document.createElement('option');
        ungrouped.value = '';
        ungrouped.textContent = 'Other';
        select.appendChild(ungrouped);
        for (const group of data.groups || []) {
            const option = document.createElement('option');
            option.value = group.name;
            option.textContent = group.name;
            option.selected = (group.sessions || []).includes(name);
            select.appendChild(option);
        }
        dialog.showModal();
    }

    byId('sidebar-session-move-form')?.addEventListener('submit', async (event) => {
        if (event.submitter?.value !== 'move') return;
        event.preventDefault();
        const dialog = byId('sidebar-session-move-dialog');
        const name = dialog.dataset.session || '';
        const group = byId('sidebar-session-move-group').value;
        dialog.close();
        if (name) await moveSession(name, group);
    });

    function updateCreateButton(type, query, names) {
        const button = byId(`${type}-create`);
        if (button) button.hidden = !query || names.includes(query) || !validName(query);
    }

    async function loadSidebar(scrollToCurrent = false) {
        for (const [id, message] of [
            ['session-list-placeholder', 'Loading sessions…'],
            ['workspace-list-placeholder', 'Loading workspaces…']
        ]) {
            const node = byId(id);
            if (!node) continue;
            const spinner = document.createElement('span');
            spinner.className = 'spinner';
            spinner.setAttribute('aria-hidden', 'true');
            const label = document.createElement('span');
            label.textContent = message;
            node.replaceChildren(spinner, label);
            node.hidden = false;
        }
        try {
            const [sessions, groups] = await Promise.all([
                api('/api/session/list'),
                api('/api/session/groups')
            ]);
            const selectedSession = String(sessions.selected || '').trim();
            const pageSession = String(document.body.dataset.maiaSession || selectedSession).trim();
            const pageWorkspace = String(document.body.dataset.maiaWorkspace || '').trim();
            const settingsResponse = await fetch(url('/api/session/settings'), {
                headers: pageSession ? { 'X-MAIA-Session': pageSession } : {}
            });
            const settings = await settingsResponse.json();
            if (!settingsResponse.ok || !settings.ok) {
                throw new Error(settings.error || 'Unable to load workspaces and profiles.');
            }
            const sessionItems = sessions.sessions || [];
            data.sessions = sessionItems.map((item) => String(item.name || '')).filter(Boolean);
            data.groups = Array.isArray(groups.groups) ? groups.groups : [];
            data.workspaces = (settings.workspaces || []).map(String);
            data.currentSession = pageSession;
            const currentSessionItem = sessionItems.find((item) => String(item.name || '') === pageSession);
            data.currentWorkspace = pageWorkspace
                || String(settings.workspace || currentSessionItem?.workspace || '').trim();
            for (const type of ['session', 'workspace']) renderNames(type, scrollToCurrent);
        } catch (error) {
            for (const id of ['session-list-placeholder', 'workspace-list-placeholder']) {
                const node = byId(id);
                if (node) { node.hidden = false; node.textContent = error.message; }
            }
        }
    }

    function confirmWorkspaceDirectory(name, path) {
        const dialog = byId('sidebar-workspace-directory-dialog');
        const message = byId('sidebar-workspace-directory-message');
        const prompt = `The directory "${path}" for workspace "${name}" does not exist. Create it?`;
        if (!dialog || !message) return Promise.resolve(false);
        message.textContent = prompt;
        dialog.returnValue = '';

        if (typeof dialog.showModal === 'function') {
            return new Promise((resolve) => {
                dialog.addEventListener('close', () => resolve(dialog.returnValue === 'create'), { once: true });
                dialog.showModal();
            });
        }

        // Fallback for browsers without modal <dialog> support. Keep the prompt
        // in-page rather than relying on a native confirm after an async request.
        return new Promise((resolve) => {
            const backdrop = document.createElement('div');
            backdrop.setAttribute('aria-hidden', 'true');
            Object.assign(backdrop.style, {
                position: 'fixed', inset: '0', zIndex: '10000',
                background: 'rgb(0 0 0 / 40%)'
            });
            const originalStyle = dialog.getAttribute('style');
            Object.assign(dialog.style, {
                display: 'block', position: 'fixed', left: '50%', top: '50%',
                transform: 'translate(-50%, -50%)', margin: '0', zIndex: '10001',
                background: 'Canvas', boxShadow: '0 0 0 100vmax rgb(0 0 0 / 40%)'
            });
            dialog.setAttribute('open', '');
            const form = dialog.querySelector('form');
            const finish = (accepted) => {
                form?.removeEventListener('click', onClick);
                document.removeEventListener('keydown', onKeyDown);
                backdrop.removeEventListener('click', onCancel);
                backdrop.remove();
                dialog.removeAttribute('open');
                if (originalStyle === null) dialog.removeAttribute('style');
                else dialog.setAttribute('style', originalStyle);
                resolve(accepted);
            };
            const onClick = (event) => {
                const button = event.target instanceof Element ? event.target.closest('button[value]') : null;
                if (!button || !form?.contains(button)) return;
                event.preventDefault();
                finish(button.value === 'create');
            };
            const onCancel = () => finish(false);
            const onKeyDown = (event) => {
                if (event.key === 'Escape') {
                    event.preventDefault();
                    finish(false);
                }
            };
            form?.addEventListener('click', onClick);
            document.addEventListener('keydown', onKeyDown);
            backdrop.addEventListener('click', onCancel);
            document.body.appendChild(backdrop);
            document.body.appendChild(dialog);
            dialog.querySelector('button[value="create"]')?.focus();
        });
    }

    async function showInputDialog(title, label, value, action = title) {
        const dialog = byId('sidebar-input-dialog');
        const input = byId('sidebar-input-value');
        if (!dialog || !input || typeof dialog.showModal !== 'function') {
            return window.prompt(`${title}\n${label}:`, value);
        }
        byId('sidebar-input-title').textContent = title;
        byId('sidebar-input-label').firstChild.textContent = label;
        const confirmButton = byId('sidebar-input-confirm');
        confirmButton.textContent = action;
        window.maiaUi.setActionType(confirmButton, 'action-normal');
        input.value = value;
        dialog.returnValue = '';
        return new Promise((resolve) => {
            dialog.addEventListener('close', () => {
                resolve(dialog.returnValue === 'confirm' ? input.value : null);
            }, { once: true });
            dialog.showModal();
            input.focus();
            input.select();
        });
    }

    async function createResource(type, name, source = '') {
        const body = { name };
        if (type === 'workspace') {
            body.path = await showInputDialog('Create', 'Workspace directory relative to MAIA home', name, 'Create') || '';
            if (!body.path) return;
        } else if (source) {
            body.source = source;
        }
        const endpoint = type === 'session' ? '/api/session/create' : '/api/workspace/create';
        const create = () => api(endpoint, {
            method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body)
        });
        try {
            await create();
        } catch (error) {
            const missingWorkspaceDirectory = error.code === 'workspace_path_missing' ||
                error.status === 409 || error.message === 'The workspace directory does not exist.';
            if (type !== 'workspace' || !missingWorkspaceDirectory) throw error;
            const shouldCreate = await confirmWorkspaceDirectory(name, body.path);
            if (!shouldCreate) return;
            body.createPath = true;
            await create();
        }
        if (type === 'session') {
            window.location.href = url(`/session/${encodeURIComponent(name)}`);
        } else {
            await loadSidebar();
        }
    }

    async function renameSession(oldName) {
        const name = await showInputDialog('Rename', 'Session name', oldName, 'Rename');
        if (!name || name === oldName) return;
        if (!validName(name)) { setError('Invalid session name.'); return; }
        if (data.sessions.includes(name)) { setError(`Session '${name}' already exists.`); return; }
        const operation = beginSessionOperation(oldName, 'Renaming');
        if (!operation) return;

        // Optimistically rename the session in the sidebar while the server operation runs.
        data.sessions = data.sessions.map((session) => session === oldName ? name : session);
        for (const group of data.groups || []) {
            group.sessions = (group.sessions || []).map((session) => session === oldName ? name : session);
        }
        pendingSessionOperations.delete(oldName);
        pendingSessionOperations.set(name, operation);
        renderSessionGroups(false);

        try {
            await api('/api/session/rename', {
                method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ oldName, newName: name })
            });
        } catch (error) {
            data.sessions = data.sessions.map((session) => session === name ? oldName : session);
            for (const group of data.groups || []) {
                group.sessions = (group.sessions || []).map((session) => session === name ? oldName : session);
            }
            setError(error.message);
        } finally {
            await finishSessionOperation(name, operation);
        }
    }

    async function copySession(source) {
        const name = await showInputDialog('Copy', `Name for the copy of '${source}'`, `${source}-copy`, 'Copy');
        if (!name) return;
        if (!validName(name)) { setError('Invalid session name.'); return; }
        try { await createResource('session', name, source); }
        catch (error) { setError(error.message); }
    }

    async function deleteSession(name) {
        if (!await confirmSidebarAction('Remove session', `Permanently delete session '${name}' and its history? This cannot be undone.`, 'Remove', 'action-warning')) return;
        const operation = beginSessionOperation(name, 'Deleting');
        if (!operation) return;
        try {
            await api('/api/session/delete', {
                method: 'POST', headers: { 'Content-Type': 'text/plain; charset=utf-8' }, body: name
            });
            // Keep the blank pending row until the whole batch settles and the list refreshes.
            operation.completed = true;
        } catch (error) {
            setError(error.message);
        } finally {
            await finishSessionOperation(name, operation);
        }
    }

    async function deleteResource(type, name, button) {
        if (!await confirmSidebarAction('Remove workspace', `Remove workspace '${name}'? Its files will not be deleted.`, 'Remove', 'action-check')) return;
        setBusy(button, `Deleting workspace ${name}…`);
        try {
            await api('/api/workspace/delete', {
                method: 'POST', headers: { 'Content-Type': 'text/plain; charset=utf-8' }, body: name
            });
            await loadSidebar();
        } catch (error) { setError(error.message); }
        finally { clearBusy(button); }
    }

    async function editWorkspace(name) {
        const endpoint = `/api/workspace/settings?name=${encodeURIComponent(name)}`;
        try {
            const settings = await api(endpoint);
            const value = await showInputDialog('Update', 'Workspace path relative to MAIA home', settings.path || '', 'Update');
            if (value === null) return;
            await api(endpoint, {
                method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ path: value })
            });
            await loadSidebar();
        } catch (error) { setError(error.message); }
    }

    function fillSelect(select, values, selected, multiple = false) {
        select.replaceChildren();
        const options = [...new Set(['', ...(values || [])])];
        for (const value of options) {
            const option = document.createElement('option');
            option.value = value;
            option.textContent = value || '(none)';
            option.selected = multiple ? (selected || []).includes(value) : value === selected;
            select.appendChild(option);
        }
    }

    async function openSessionSettings(name) {
        const dialog = byId('sidebar-session-settings');
        if (!dialog) { window.location.href = url(`/session/${encodeURIComponent(name)}`); return; }
        dialog.dataset.session = name;
        byId('sidebar-session-settings-title').textContent = `Session settings: ${name}`;
        byId('sidebar-session-settings-status').textContent = 'Loading settings…';
        dialog.showModal();
        try {
            const response = await fetch(url('/api/session/settings'), { headers: { 'X-MAIA-Session': name } });
            const result = await response.json();
            if (!response.ok || !result.ok) throw new Error(result.error || 'Unable to load session settings.');
            fillSelect(byId('sidebar-setting-profile'), result.profiles, result.profile);
            fillSelect(byId('sidebar-setting-workspace'), result.workspaces, result.workspace);
            fillSelect(byId('sidebar-setting-filesets'), result.filesetOptions, result.filesets, true);
            fillSelect(byId('sidebar-setting-extra-filesets'), result.filesetOptions, result.extraSendFilesets, true);
            byId('sidebar-session-settings-status').textContent = '';
        } catch (error) { byId('sidebar-session-settings-status').textContent = error.message; }
    }

    byId('sidebar-session-settings-form')?.addEventListener('submit', async (event) => {
        if (event.submitter?.value !== 'save') return;
        event.preventDefault();
        const dialog = byId('sidebar-session-settings');
        const name = dialog.dataset.session;
        const button = byId('sidebar-session-settings-save');
        setBusy(button, 'Saving settings…');
        try {
            const body = {
                profile: byId('sidebar-setting-profile').value,
                workspace: byId('sidebar-setting-workspace').value,
                filesets: Array.from(byId('sidebar-setting-filesets').selectedOptions).map((item) => item.value).filter(Boolean),
                extraSendFilesets: Array.from(byId('sidebar-setting-extra-filesets').selectedOptions).map((item) => item.value).filter(Boolean)
            };
            const response = await fetch(url('/api/session/settings'), {
                method: 'POST', headers: { 'Content-Type': 'application/json', 'X-MAIA-Session': name },
                body: JSON.stringify(body)
            });
            const result = await response.json();
            if (!response.ok || !result.ok) throw new Error(result.error || 'Unable to save session settings.');
            byId('sidebar-session-settings-status').textContent = 'Saved.';
            await loadSidebar();
        } catch (error) { byId('sidebar-session-settings-status').textContent = error.message; }
        finally { clearBusy(button); }
    });

    byId('session-group-create')?.addEventListener('click', () => createSessionGroup());

    for (const type of ['session', 'workspace']) {
        const form = byId(`${type}-search`);
        const input = byId(`${type}-search-input`);
        input?.addEventListener('input', () => {
            if (type === 'session') expandedSearchGroups.clear();
            renderNames(type);
        });
        byId(`${type}-create`)?.addEventListener('click', async () => {
            const name = input?.value.trim() || '';
            if (!name || !validName(name)) return;
            try { await createResource(type, name); }
            catch (error) { setError(error.message); }
        });
        form?.addEventListener('submit', async (event) => {
            event.preventDefault();
            const name = input?.value.trim() || '';
            if (!name) return;
            if ((data[`${type}s`] || []).includes(name)) {
                window.location.href = type === 'session'
                    ? url(`/session/${encodeURIComponent(name)}`)
                    : url(`/${type}/${encodeURIComponent(name)}`);
                return;
            }
            if (!validName(name)) { setError(`Invalid ${type} name.`); return; }
            try { await createResource(type, name); }
            catch (error) { setError(error.message); }
        });
    }

    document.addEventListener('scroll', () => {
        document.querySelectorAll('.sidebar-item-menu-floating').forEach((menu) => {
            const context = actionMenuContexts.get(menu);
            if (context) positionActionMenu(menu, context.toggle);
        });
    }, true);

    const sidebar = byId('sidebar');
    const toggle = byId('sidebar-toggle');
    const backdrop = byId('sidebar-backdrop');
    function setSidebarOpen(open) {
        document.body.classList.toggle('sidebar-open', open);
        sidebar?.classList.toggle('open', open);
        backdrop?.classList.toggle('visible', open);
        toggle?.setAttribute('aria-expanded', String(open));
        sidebar?.setAttribute('aria-hidden', String(!open));
        if (open) requestAnimationFrame(() => scrollCurrentIntoView(byId('session-list')));
    }
    toggle?.addEventListener('click', () => setSidebarOpen(!sidebar?.classList.contains('open')));
    byId('sidebar-close')?.addEventListener('click', () => setSidebarOpen(false));
    const refresh = byId('sidebar-refresh');
    refresh?.addEventListener('click', async () => {
        setBusy(refresh, 'Refreshing sessions and workspaces…');
        try { await loadSidebar(); }
        finally { clearBusy(refresh); }
    });
    backdrop?.addEventListener('click', () => setSidebarOpen(false));
    document.addEventListener('keydown', (event) => { if (event.key === 'Escape') setSidebarOpen(false); });

    loadSidebar();
})();
