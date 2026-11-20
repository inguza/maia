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
    let sidebarLoadPromise = null;
    let sidebarRefreshRequested = false;
    let sidebarDataReady = false;
    let sidebarOpenNeedsCurrentReveal = false;
    let sidebarMutationVersion = 0;
    let sidebarOperationBatchVersion = 0;
    let inlineCreation = null;

    let sidebarMutationQueue = Promise.resolve();

    function queueSidebarMutation(callback) {
        const result = sidebarMutationQueue.then(callback);
        sidebarMutationQueue = result.catch(() => {});
        return result;
    }

    function beginSidebarOperation(action) {
        const operation = { action };
        pendingOperations.add(operation);
        sidebarMutationVersion += 1;
        sidebarOperationBatchVersion += 1;
        return operation;
    }

    async function finishSidebarOperation(operation) {
        pendingOperations.delete(operation);
        const batchVersion = ++sidebarOperationBatchVersion;
        if (pendingOperations.size > 0) {
            renderSessionGroups(false);
            return;
        }

        // Keep the completed rows' spinners briefly so quick consecutive actions
        // join the same batch instead of racing an immediate sidebar refresh.
        await new Promise((resolve) => window.setTimeout(resolve, 200));
        if (batchVersion !== sidebarOperationBatchVersion || pendingOperations.size > 0) return;

        clearCompletedSessionOperations();
        clearCompletedGroupOperations();
        sidebarRefreshRequested = true;
        await loadSidebar(false);
    }

    function setError(message) {
        let element = byId('sidebar-error');
        if (!element) {
            const sidebar = byId('sidebar');
            if (!sidebar) return;
            element = document.createElement('p');
            element.id = 'sidebar-error';
            element.className = 'error';
            element.setAttribute('role', 'alert');
            sidebar.prepend(element);
        }
        element.textContent = message;
        element.hidden = !message;
        if (message) {
            setSidebarOpen(true);
            element.scrollIntoView({ block: 'nearest' });
        }
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

    function createSidebarIconElement(kind) {
        const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
        svg.setAttribute('viewBox', '0 0 24 24');
        svg.setAttribute('aria-hidden', 'true');
        const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
        if (kind === 'folder-plus') {
            path.setAttribute('d', 'M3 6.5h7l2 2H21v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z M16 12v5 M13.5 14.5h5');
        } else {
            path.setAttribute('d', 'M4 5.5h16v11H11l-5 3v-3H4z M15 8.5v5 M12.5 11h5');
        }
        path.setAttribute('fill', 'none');
        path.setAttribute('stroke', 'currentColor');
        path.setAttribute('stroke-width', '1.8');
        path.setAttribute('stroke-linecap', 'round');
        path.setAttribute('stroke-linejoin', 'round');
        svg.appendChild(path);
        return svg;
    }

    function createSidebarIconButton(kind, title, handler, extraClass = '') {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = `sidebar-small-button sidebar-icon-button ${extraClass}`.trim();
        button.title = title;
        button.setAttribute('aria-label', title);
        button.appendChild(createSidebarIconElement(kind));
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

    function sessionSubsessionNames(name) {
        return (data.sessions || [])
            .filter((session) => session.startsWith(`${name}%`))
            .sort((a, b) => b.split('%').length - a.split('%').length || a.localeCompare(b));
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
        const subsessions = sessionSubsessionNames(name);
        const actions = [
            { icon: '\u2699\uFE0E', label: 'Settings', run: () => openSessionSettings(name) },
            { icon: '\u270E', label: 'Rename', run: () => renameSession(name) },
            { icon: '\u29C9', label: 'Copy', run: () => copySession(name) },
            { icon: '\u21C4', label: 'Move', run: () => openSessionMoveDialog(name) }
        ];
        if (subsessions.length) {
            actions.push(
                { icon: '\u00D7\u21A7', label: 'Delete tree', run: () => deleteSession(name, 'tree') },
                { icon: '\u00D7\u2193', label: 'Delete subsessions', run: () => deleteSession(name, 'subsessions') }
            );
        }
        actions.push(
            { icon: '\u00D7', label: 'Delete', run: () => deleteSession(name) },
            { iconFactory: () => createSidebarIconElement('chat-plus'), label: 'New subsession', run: () => createChildSession(name) }
        );
        row.appendChild(createActionMenu(name, actions));
        return row;
    }

    function createVirtualSessionRow(name, displayName) {
        const row = document.createElement('div');
        row.className = 'sidebar-session-row sidebar-session-virtual-row';
        const label = document.createElement('span');
        label.className = 'sidebar-session-virtual-name';
        label.textContent = displayName;
        row.appendChild(label);
        const actions = [{
            iconFactory: () => createSidebarIconElement('chat-plus'),
            label: 'Create session', run: () => createSidebarSession(name)
        }];
        if (sessionSubsessionNames(name).length) {
            actions.push({
                icon: '\u00D7\u2193', label: 'Delete subsessions',
                run: () => deleteSession(name, 'subsessions')
            });
        }
        actions.push({
            iconFactory: () => createSidebarIconElement('chat-plus'),
            label: 'New subsession', run: () => createChildSession(name)
        });
        row.appendChild(createActionMenu(`virtual session ${name}`, actions));
        return row;
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
            const creatingChild = inlineCreation?.type === 'subsession' && inlineCreation.parentName === node.name;
            const hasChildren = childList.children.length > 0 || creatingChild;
            if (!includeSelf && !hasChildren) continue;

            const item = document.createElement('li');
            item.className = 'sidebar-session-tree-item';
            item.dataset.session = node.name;
            if (hasChildren) {
                const treeNode = document.createElement('div');
                treeNode.className = 'sidebar-session-tree-node';
                const header = document.createElement('div');
                header.className = 'sidebar-session-tree-summary';
                const sessionExpansionKey = `session:${node.name}`;
                const isCurrentAncestor = Boolean(data.currentSession && data.currentSession.startsWith(`${node.name}%`));
                const isExpanded = Boolean(expression || (expandedGroups.has(sessionExpansionKey)
                    ? expandedGroups.get(sessionExpansionKey)
                    : isCurrentAncestor));
                const toggle = document.createElement('button');
                toggle.type = 'button';
                toggle.className = 'sidebar-tree-toggle';
                toggle.textContent = isExpanded ? '\u25BE' : '\u25B8';
                toggle.setAttribute('aria-expanded', String(isExpanded));
                toggle.setAttribute('aria-label', `${isExpanded ? 'Collapse' : 'Expand'} ${treeLabel(node.name)}`);
                toggle.addEventListener('click', () => {
                    const nextExpanded = toggle.getAttribute('aria-expanded') !== 'true';
                    expandedGroups.set(`session:${node.name}`, nextExpanded);
                    toggle.setAttribute('aria-expanded', String(nextExpanded));
                    toggle.setAttribute('aria-label', `${nextExpanded ? 'Collapse' : 'Expand'} ${treeLabel(node.name)}`);
                    toggle.textContent = nextExpanded ? '\u25BE' : '\u25B8';
                    childList.hidden = !nextExpanded;
                });
                header.appendChild(toggle);
                if (includeSelf) header.appendChild(createSessionRow(node.name, treeLabel(node.name)));
                else header.appendChild(createVirtualSessionRow(node.name, treeLabel(node.name)));
                treeNode.appendChild(header);
                if (creatingChild) treeNode.appendChild(createInlineCreator('subsession', node.name));
                treeNode.appendChild(childList);
                childList.hidden = !isExpanded;
                item.appendChild(treeNode);
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
        const groupNames = new Set(groupRecords.keys());
        for (const [name, operation] of pendingGroupOperations) {
            if (operation.action === 'Removing') groupNames.add(name);
        }
        const groupTree = buildNameTree(Array.from(groupNames), groupRecords);
        const memberships = new Set();
        const currentGroupPaths = new Set();
        for (const group of data.groups || []) {
            for (const name of group.sessions || []) memberships.add(name);
            if (data.currentSession && (group.sessions || []).includes(data.currentSession)) {
                let prefix = '';
                for (const part of String(group.name).split('%')) {
                    prefix = prefix ? `${prefix}%${part}` : part;
                    currentGroupPaths.add(prefix);
                }
            }
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
            const pendingGroupOperation = pendingGroupOperations.get(name);
            const removing = pendingGroupOperation?.action === 'Removing';
            const groupMatches = Boolean(expression && !invalidRegex && expression.test(name));
            const showAllForSearch = Boolean(query && (inheritedShowAll ||
                (groupMatches && expandedSearchGroups.has(name))));
            const members = group
                ? sessions.filter((session) => (group.sessions || []).includes(session))
                : [];
            const memberTree = makeSessionTree(members, showAllForSearch);
            const childSections = node.children.map((child) => renderGroupNode(child, showAllForSearch)).filter(Boolean);
            const visible = removing || !query || groupMatches || memberTree.children.length > 0 || childSections.length > 0;
            if (!visible) return null;

            const section = document.createElement('section');
            section.className = group ? 'sidebar-session-group' : 'sidebar-session-group sidebar-virtual-group';
            if (removing) section.classList.add('sidebar-session-group-removing');
            if (group) section.dataset.group = name;
            if (currentGroupPaths.has(name)) section.classList.add('sidebar-current-group');
            const groupExpansionKey = `group:${name}`;
            const expanded = query ? true : expandedGroups.has(groupExpansionKey)
                ? Boolean(expandedGroups.get(groupExpansionKey))
                : currentGroupPaths.has(name);
            const header = document.createElement('div');
            header.className = 'sidebar-session-group-header';
            if (removing) {
                const spinner = document.createElement('span');
                spinner.className = 'spinner';
                spinner.setAttribute('role', 'status');
                spinner.setAttribute('aria-label', `Removing group ${name}`);
                spinner.title = `Removing group ${name}`;
                header.appendChild(spinner);
                section.appendChild(header);
                hasVisibleSection = true;
                return section;
            }
            if (group) {
                header.addEventListener('dragover', (event) => {
                    event.preventDefault();
                    event.stopPropagation();
                    section.classList.add('sidebar-group-drop-target');
                });
                header.addEventListener('dragleave', (event) => {
                    event.stopPropagation();
                    if (!header.contains(event.relatedTarget)) section.classList.remove('sidebar-group-drop-target');
                });
                header.addEventListener('drop', (event) => {
                    event.preventDefault();
                    event.stopPropagation();
                    section.classList.remove('sidebar-group-drop-target');
                    const session = event.dataTransfer?.getData('text/plain') || '';
                    if (session) moveSession(session, name);
                });
            }
            const content = document.createElement('div');
            content.className = 'sidebar-session-group-content';
            content.hidden = !expanded;
            if (members.length > 0 || childSections.length > 0) {
                const toggle = document.createElement('button');
                toggle.type = 'button';
                toggle.className = 'sidebar-tree-toggle';
                toggle.textContent = expanded ? '\u25BE' : '\u25B8';
                toggle.setAttribute('aria-expanded', String(expanded));
                toggle.setAttribute('aria-label', `${expanded ? 'Collapse' : 'Expand'} ${treeLabel(name)}`);
                toggle.addEventListener('click', () => {
                    const nextExpanded = toggle.getAttribute('aria-expanded') !== 'true';
                    expandedGroups.set(`group:${name}`, nextExpanded);
                    toggle.setAttribute('aria-expanded', String(nextExpanded));
                    toggle.setAttribute('aria-label', `${nextExpanded ? 'Collapse' : 'Expand'} ${treeLabel(name)}`);
                    toggle.textContent = nextExpanded ? '\u25BE' : '\u25B8';
                    content.hidden = !nextExpanded;
                });
                header.appendChild(toggle);
            } else {
                const spacer = document.createElement('span');
                spacer.className = 'sidebar-tree-toggle-spacer';
                header.appendChild(spacer);
            }
            const label = document.createElement('span');
            label.className = 'sidebar-group-name';
            label.textContent = treeLabel(name);
            header.appendChild(label);
            if (group && pendingGroupOperation) {
                const spinner = document.createElement('span');
                spinner.className = 'spinner sidebar-session-move-spinner';
                spinner.setAttribute('role', 'status');
                spinner.setAttribute('aria-label', `${pendingGroupOperation.action} group ${name}`);
                spinner.title = `${pendingGroupOperation.action} group ${name}`;
                header.appendChild(spinner);
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
                header.appendChild(showAll);
            }
            const groupActions = group ? [
                {
                    iconFactory: () => createSidebarIconElement('folder-plus'),
                    label: 'New subgroup',
                    title: `Create subgroup under ${name}`,
                    ariaLabel: `Create subgroup under ${name}`,
                    run: () => createSessionGroup(name)
                },
                {
                    iconFactory: () => createSidebarIconElement('chat-plus'),
                    label: 'New session',
                    title: `Create session in ${name}`,
                    ariaLabel: `Create session in ${name}`,
                    run: () => createSessionInGroup(name)
                },
                { icon: '\u00D7', label: 'Delete', run: () => deleteGroup(name) },
                { icon: '\u270E', label: 'Rename', run: () => renameSessionGroup(name) }
            ] : [
                {
                    iconFactory: () => createSidebarIconElement('folder-plus'),
                    label: 'Create group',
                    title: `Create group ${name}`,
                    ariaLabel: `Create group ${name}`,
                    run: () => createSessionGroup('', name)
                }
            ];
            header.appendChild(createActionMenu(name, groupActions));

            if (memberTree.children.length) content.appendChild(memberTree);
            if ((inlineCreation?.type === 'group' || inlineCreation?.type === 'session') && inlineCreation.parentName === name) {
                content.appendChild(createInlineCreator(inlineCreation.type, name));
            }
            if (childSections.length) {
                const children = document.createElement('div');
                children.className = 'sidebar-subgroups';
                for (const child of childSections) children.appendChild(child);
                content.appendChild(children);
            }
            section.append(header, content);
            hasVisibleSection = true;
            return section;
        };

        if (inlineCreation?.type === 'group' && !inlineCreation.parentName) {
            list.appendChild(createInlineCreator('group', ''));
        }
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
            const section = document.createElement('section');
            section.className = 'sidebar-session-group sidebar-ungrouped-group';
            if (data.currentSession && !memberships.has(data.currentSession)) {
                section.classList.add('sidebar-current-group');
            }
            const expanded = query ? true : expandedGroups.has('Ungrouped')
                ? Boolean(expandedGroups.get('Ungrouped'))
                : Boolean(data.currentSession && !memberships.has(data.currentSession));
            const header = document.createElement('div');
            header.className = 'sidebar-session-group-header';
            header.addEventListener('dragover', (event) => {
                event.preventDefault();
                event.stopPropagation();
                section.classList.add('sidebar-group-drop-target');
            });
            header.addEventListener('dragleave', (event) => {
                event.stopPropagation();
                if (!header.contains(event.relatedTarget)) section.classList.remove('sidebar-group-drop-target');
            });
            header.addEventListener('drop', (event) => {
                event.preventDefault();
                event.stopPropagation();
                section.classList.remove('sidebar-group-drop-target');
                const session = event.dataTransfer?.getData('text/plain') || '';
                if (session) moveSession(session, '');
            });
            const content = document.createElement('div');
            content.className = 'sidebar-session-group-content';
            content.hidden = !expanded;
            const toggle = document.createElement('button');
            toggle.type = 'button';
            toggle.className = 'sidebar-tree-toggle';
            toggle.textContent = expanded ? '\u25BE' : '\u25B8';
            toggle.setAttribute('aria-expanded', String(expanded));
            toggle.setAttribute('aria-label', `${expanded ? 'Collapse' : 'Expand'} Other`);
            toggle.addEventListener('click', () => {
                const nextExpanded = toggle.getAttribute('aria-expanded') !== 'true';
                expandedGroups.set('Ungrouped', nextExpanded);
                toggle.setAttribute('aria-expanded', String(nextExpanded));
                toggle.setAttribute('aria-label', `${nextExpanded ? 'Collapse' : 'Expand'} Other`);
                toggle.textContent = nextExpanded ? '\u25BE' : '\u25B8';
                content.hidden = !nextExpanded;
            });
            header.appendChild(toggle);
            const label = document.createElement('span');
            label.className = 'sidebar-group-name';
            label.textContent = 'Other';
            header.appendChild(label);
            if (query && ungroupedMatches) {
                const showAll = document.createElement('button');
                showAll.type = 'button';
                showAll.className = 'sidebar-group-show-all';
                showAll.textContent = showAllUngrouped ? 'Show matches' : 'Show all';
                showAll.setAttribute('aria-label', showAllUngrouped
                    ? 'Show matching ungrouped sessions'
                    : 'Show all ungrouped sessions');
                showAll.addEventListener('click', (event) => {
                    event.stopPropagation();
                    if (showAllUngrouped) expandedSearchGroups.delete('Ungrouped');
                    else expandedSearchGroups.add('Ungrouped');
                    renderSessionGroups(false);
                });
                header.appendChild(showAll);
            }
            if (ungroupedTree.children.length) content.appendChild(ungroupedTree);
            if (inlineCreation?.type === 'session' && !inlineCreation.parentName) {
                content.appendChild(createInlineCreator('session', ''));
            }
            section.append(header, content);
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

    function openInlineCreator(type, parentName = '') {
        inlineCreation = { type, parentName };
        if (parentName) {
            const parts = parentName.split('%');
            let prefix = '';
            for (const part of parts) {
                prefix = prefix ? `${prefix}%${part}` : part;
                expandedGroups.set(`group:${prefix}`, true);
                expandedGroups.set(`session:${prefix}`, true);
            }
        } else if (type === 'session') {
            expandedGroups.set('Ungrouped', true);
        }
        renderSessionGroups(false);
        const editor = document.querySelector('.sidebar-inline-create input');
        editor?.focus();
    }

    function createInlineCreator(type, parentName = '') {
        const form = document.createElement('form');
        form.className = 'sidebar-inline-create';
        const input = document.createElement('input');
        input.type = 'text';
        input.autocomplete = 'off';
        input.required = true;
        input.placeholder = type === 'subsession' ? 'Child session name' :
            type === 'group' ? 'Group name' : 'Session name';
        input.setAttribute('aria-label', input.placeholder);
        const actions = document.createElement('div');
        actions.className = 'sidebar-inline-create-actions';
        const cancel = document.createElement('button');
        cancel.type = 'button';
        cancel.className = 'action-cancel';
        cancel.textContent = 'Cancel';
        cancel.addEventListener('click', () => {
            inlineCreation = null;
            renderSessionGroups(false);
        });
        const submit = document.createElement('button');
        submit.type = 'submit';
        submit.className = 'action-normal';
        submit.textContent = type === 'group' ? 'Create group' : 'Create session';
        actions.append(cancel, submit);
        form.append(input, actions);
        form.addEventListener('keydown', (event) => {
            if (event.key === 'Escape') {
                event.preventDefault();
                inlineCreation = null;
                renderSessionGroups(false);
            }
        });
        form.addEventListener('submit', async (event) => {
            event.preventDefault();
            const value = input.value.trim();
            if (!value) return;
            inlineCreation = null;
            renderSessionGroups(false);
            if (type === 'group') {
                await createSessionGroup(parentName, value);
            } else if (type === 'subsession') {
                if (value.includes('%')) { setError('Enter one child name without the % separator.'); return; }
                await createSidebarSession(`${parentName}%${value}`);
            } else {
                await createSidebarSession(value, parentName);
            }
        });
        return form;
    }

    async function createSidebarSession(name, groupName = '') {
        if (!validName(name)) { setError('Invalid session name.'); return; }
        if ((data.sessions || []).includes(name)) {
            setError(`Session '${name}' already exists.`);
            return;
        }
        const destination = groupName
            ? (data.groups || []).find((group) => group.name === groupName)
            : null;
        if (groupName && !destination) {
            setError(`Group '${groupName}' does not exist.`);
            return;
        }

        const operation = beginSidebarOperation('Creating');
        pendingSessionOperations.set(name, operation);
        data.sessions.push(name);
        if (destination) {
            destination.sessions.push(name);
            let prefix = '';
            for (const part of groupName.split('%')) {
                prefix = prefix ? `${prefix}%${part}` : part;
                expandedGroups.set(`group:${prefix}`, true);
            }
        } else {
            expandedGroups.set('Ungrouped', true);
        }
        const parts = name.split('%');
        let prefix = '';
        for (const part of parts.slice(0, -1)) {
            prefix = prefix ? `${prefix}%${part}` : part;
            expandedGroups.set(`session:${prefix}`, true);
        }
        renderSessionGroups(false);

        let created = false;
        try {
            await queueSidebarMutation(async () => {
                await api('/api/session/create', {
                    method: 'POST', headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ name })
                });
                created = true;
                if (groupName) {
                    await api('/api/session/groups', {
                        method: 'POST', headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ action: 'move', session: name, group: groupName })
                    });
                }
            });
            operation.completed = true;
        } catch (error) {
            if (!created) data.sessions = data.sessions.filter((session) => session !== name);
            if (destination) {
                destination.sessions = (destination.sessions || []).filter((session) => session !== name);
            }
            setError(created && groupName
                ? `Session '${name}' was created, but could not be added to '${groupName}': ${error.message}`
                : error.message);
        } finally {
            await finishSessionOperation(name, operation);
        }
    }

    function createTopLevelSession() {
        openInlineCreator('session');
    }

    function createSessionInGroup(groupName) {
        openInlineCreator('session', groupName);
    }

    function createChildSession(parentName) {
        openInlineCreator('subsession', parentName);
    }

    async function createSessionGroup(parentName = '', childName = null) {
        if (childName === null) {
            openInlineCreator('group', parentName);
            return;
        }
        childName = childName.trim();
        if (!childName) return;
        if (parentName && childName.includes('%')) {
            setError('Enter one child name without the % separator.');
            return;
        }
        const groupName = parentName ? `${parentName}%${childName}` : childName;
        if (!validName(groupName)) { setError('Invalid group name.'); return; }
        if ((data.groups || []).some((group) => group.name === groupName)) {
            if (parentName && !childName) return;
            setError(`Group '${groupName}' already exists.`);
            return;
        }

        const operation = beginSidebarOperation('Creating');
        pendingGroupOperations.set(groupName, operation);
        data.groups.push({ name: groupName, sessions: [] });
        const parts = groupName.split('%');
        let prefix = '';
        for (const part of parts) {
            prefix = prefix ? `${prefix}%${part}` : part;
            expandedGroups.set(`group:${prefix}`, true);
        }
        renderSessionGroups(false);
        try {
            await queueSidebarMutation(() => api('/api/session/groups', {
                method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ action: 'create', name: groupName })
            }));
            operation.completed = true;
        } catch (error) {
            data.groups = data.groups.filter((group) => group.name !== groupName);
            if (pendingGroupOperations.get(groupName) === operation) {
                pendingGroupOperations.delete(groupName);
            }
            setError(error.message);
        } finally {
            await finishSidebarOperation(operation);
        }
    }

    async function renameSessionGroup(oldName) {
        const newName = await showInputDialog('Rename', 'Group name', oldName, 'Rename');
        if (!newName || newName === oldName) return;
        if (!validName(newName)) { setError('Invalid group name.'); return; }
        const previousGroups = (data.groups || []).map((group) => ({ ...group, sessions: [...(group.sessions || [])] }));
        const renamedNames = new Map();
        for (const group of previousGroups) {
            if (group.name === oldName || group.name.startsWith(`${oldName}%`)) {
                renamedNames.set(group.name, `${newName}${group.name.slice(oldName.length)}`);
            }
        }
        if (!renamedNames.has(oldName)) { setError(`Group '${oldName}' does not exist.`); return; }
        for (const targetName of renamedNames.values()) {
            if ((data.groups || []).some((group) => group.name === targetName && !renamedNames.has(group.name))) {
                setError(`Group '${targetName}' already exists.`);
                return;
            }
        }

        const operation = beginSidebarOperation('Renaming');
        data.groups = previousGroups.map((group) => ({
            ...group,
            name: renamedNames.get(group.name) || group.name
        }));
        for (const [oldGroupName, newGroupName] of renamedNames) {
            pendingGroupOperations.delete(oldGroupName);
            pendingGroupOperations.set(newGroupName, operation);
            const wasExpanded = expandedGroups.get(`group:${oldGroupName}`);
            if (wasExpanded !== undefined) expandedGroups.set(`group:${newGroupName}`, wasExpanded);
            expandedGroups.delete(`group:${oldGroupName}`);
            if (expandedSearchGroups.delete(oldGroupName)) expandedSearchGroups.add(newGroupName);
        }
        renderSessionGroups(false);
        try {
            await queueSidebarMutation(() => api('/api/session/groups', {
                method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ action: 'rename', oldName, newName })
            }));
            operation.completed = true;
        } catch (error) {
            data.groups = previousGroups;
            for (const [oldGroupName, newGroupName] of renamedNames) {
                if (pendingGroupOperations.get(newGroupName) === operation) pendingGroupOperations.delete(newGroupName);
                pendingGroupOperations.delete(oldGroupName);
                const wasExpanded = expandedGroups.get(`group:${newGroupName}`);
                if (wasExpanded !== undefined) expandedGroups.set(`group:${oldGroupName}`, wasExpanded);
                expandedGroups.delete(`group:${newGroupName}`);
                if (expandedSearchGroups.delete(newGroupName)) expandedSearchGroups.add(oldGroupName);
            }
            setError(error.message);
        } finally {
            await finishSidebarOperation(operation);
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
        const operation = beginSidebarOperation('Removing');
        const previousGroup = (data.groups || []).find((group) => group.name === name);
        pendingGroupOperations.set(name, operation);
        data.groups = (data.groups || []).filter((group) => group.name !== name);
        renderSessionGroups(false);
        try {
            await queueSidebarMutation(() => api('/api/session/groups', {
                method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ action: 'delete', name })
            }));
            expandedGroups.delete(`group:${name}`);
            operation.completed = true;
        } catch (error) {
            if (previousGroup && !(data.groups || []).some((group) => group.name === name)) {
                data.groups.push(previousGroup);
            }
            pendingGroupOperations.delete(name);
            setError(error.message);
        } finally {
            await finishSidebarOperation(operation);
        }
    }

    function beginSessionOperation(name, action) {
        if (pendingSessionOperations.has(name)) return null;
        const operation = beginSidebarOperation(action);
        pendingSessionOperations.set(name, operation);
        renderSessionGroups(false);
        return operation;
    }

    function clearCompletedSessionOperations() {
        for (const [name, operation] of pendingSessionOperations) {
            if (operation.completed) pendingSessionOperations.delete(name);
        }
    }

    function clearCompletedGroupOperations() {
        for (const [name, operation] of pendingGroupOperations) {
            if (operation.completed) pendingGroupOperations.delete(name);
        }
    }

    async function finishSessionOperation(name, operation) {
        if (!operation.completed && pendingSessionOperations.get(name) === operation) {
            pendingSessionOperations.delete(name);
        }
        // Refresh once all pending operations settle, without scrolling to the current session.
        await finishSidebarOperation(operation);
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
                expandedGroups.set(`group:${group}`, true);
            }
        } else {
            expandedGroups.set('Ungrouped', true);
        }
        renderSessionGroups(false);

        try {
            await queueSidebarMutation(() => api('/api/session/groups', {
                method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ action: 'move', session: name, group })
            }));
            operation.completed = true;
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
        if (pendingOperations.size > 0) {
            sidebarRefreshRequested = true;
            return;
        }
        if (sidebarLoadPromise) {
            sidebarRefreshRequested = true;
            await sidebarLoadPromise;
            return;
        }
        sidebarRefreshRequested = false;
        const loadVersion = sidebarMutationVersion;
        const load = (async () => {
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
            const sessionRoute = window.location.pathname.match(/(?:^|\/)session\/([^/]+)(?:\/|$)/);
            let routeSession = '';
            if (sessionRoute) {
                try { routeSession = decodeURIComponent(sessionRoute[1]); }
                catch (_) { routeSession = sessionRoute[1]; }
            }
            const pageSession = String(document.body.dataset.maiaSession || routeSession || selectedSession).trim();
            const pageWorkspace = String(document.body.dataset.maiaWorkspace || '').trim();
            const settingsResponse = await fetch(url('/api/session/settings'), {
                headers: pageSession ? { 'X-MAIA-Session': pageSession } : {}
            });
            const settings = await settingsResponse.json();
            if (!settingsResponse.ok || !settings.ok) {
                throw new Error(settings.error || 'Unable to load workspaces and profiles.');
            }
            if (pendingOperations.size > 0 || loadVersion !== sidebarMutationVersion) {
                sidebarRefreshRequested = true;
                return;
            }
            const sessionItems = sessions.sessions || [];
            data.sessions = sessionItems.map((item) => String(item.name || '')).filter(Boolean);
            data.groups = Array.isArray(groups.groups) ? groups.groups : [];
            data.workspaces = (settings.workspaces || []).map(String);
            data.currentSession = pageSession;
            const currentSessionItem = sessionItems.find((item) => String(item.name || '') === pageSession);
            data.currentWorkspace = pageWorkspace
                || String(settings.workspace || currentSessionItem?.workspace || '').trim();
            sidebarDataReady = true;
            const revealCurrent = sidebarOpenNeedsCurrentReveal && byId('sidebar')?.classList.contains('open');
            if (revealCurrent) {
                expandCurrentSessionPath();
                sidebarOpenNeedsCurrentReveal = false;
            }
            for (const type of ['session', 'workspace']) renderNames(type, scrollToCurrent);
            if (revealCurrent) requestAnimationFrame(() => scrollCurrentIntoView(byId('session-list')));
        } catch (error) {
            for (const id of ['session-list-placeholder', 'workspace-list-placeholder']) {
                const node = byId(id);
                if (node) { node.hidden = false; node.textContent = error.message; }
            }
        }
        })();
        sidebarLoadPromise = load;
        try {
            await load;
        } finally {
            sidebarLoadPromise = null;
            if (sidebarRefreshRequested && pendingOperations.size === 0) {
                sidebarRefreshRequested = false;
                await loadSidebar(false);
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
            await queueSidebarMutation(() => api('/api/session/rename', {
                method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ oldName, newName: name })
            }));
            operation.completed = true;
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

    async function deleteSession(name, scope = 'session') {
        const subsessions = sessionSubsessionNames(name);
        const names = scope === 'tree' ? [...subsessions, name]
            : scope === 'subsessions' ? subsessions : [name];
        if (!names.length || names.some((session) => pendingSessionOperations.has(session))) return;

        const title = scope === 'tree' ? 'Delete tree'
            : scope === 'subsessions' ? 'Delete subsessions' : 'Remove session';
        const message = scope === 'tree'
            ? `Permanently delete session '${name}', all its subsessions, and their histories? This cannot be undone.`
            : scope === 'subsessions'
                ? `Permanently delete all subsessions of '${name}' and their histories? The session itself will be kept. This cannot be undone.`
                : `Permanently delete session '${name}' and its history? This cannot be undone.`;
        if (!await confirmSidebarAction(title, message, 'Remove', 'action-warning')) return;

        const operation = beginSidebarOperation('Deleting');
        for (const session of names) pendingSessionOperations.set(session, operation);
        renderSessionGroups(false);
        let deleted = false;
        try {
            await queueSidebarMutation(async () => {
                const controller = new AbortController();
                let timedOut = false;
                const timeoutId = window.setTimeout(() => {
                    timedOut = true;
                    controller.abort();
                }, 30_000);
                try {
                    await api('/api/session/delete', {
                        method: 'POST', headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ names }), signal: controller.signal
                    });
                } catch (error) {
                    if (timedOut) {
                        throw new Error('Session deletion timed out. It may still be in progress; refresh the session list to check.');
                    }
                    throw error;
                } finally {
                    window.clearTimeout(timeoutId);
                }
            });
            deleted = true;
            operation.completed = true;
            const deletedSessions = new Set(names);
            data.sessions = data.sessions.filter((session) => !deletedSessions.has(session));
            for (const group of data.groups || []) {
                group.sessions = (group.sessions || []).filter((session) => !deletedSessions.has(session));
            }
            renderSessionGroups(false);
        } catch (error) {
            setError(error.message);
        } finally {
            if (deleted && names.includes(data.currentSession)) {
                window.location.assign(url('/'));
            } else {
                if (!operation.completed) {
                    for (const session of names) {
                        if (pendingSessionOperations.get(session) === operation) pendingSessionOperations.delete(session);
                    }
                }
                await finishSidebarOperation(operation);
            }
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

    byId('session-group-create')?.appendChild(createSidebarIconButton(
        'folder-plus', 'Create session group', () => createSessionGroup(), 'sidebar-session-create-group-icon'
    ).firstChild);
    byId('session-group-create')?.addEventListener('click', () => createSessionGroup());
    byId('session-create-top')?.appendChild(createSidebarIconButton(
        'chat-plus', 'Create session', () => createTopLevelSession(), 'sidebar-session-create-top-icon'
    ).firstChild);
    byId('session-create-top')?.addEventListener('click', () => createTopLevelSession());

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
    function expandCurrentSessionPath() {
        const current = data.currentSession;
        if (!current) return;

        const sessionParts = current.split('%');
        let sessionPrefix = '';
        for (const part of sessionParts.slice(0, -1)) {
            sessionPrefix = sessionPrefix ? `${sessionPrefix}%${part}` : part;
            expandedGroups.set(`session:${sessionPrefix}`, true);
        }

        let isGrouped = false;
        for (const group of data.groups || []) {
            if (!(group.sessions || []).includes(current)) continue;
            isGrouped = true;
            let groupPrefix = '';
            for (const part of String(group.name).split('%')) {
                groupPrefix = groupPrefix ? `${groupPrefix}%${part}` : part;
                expandedGroups.set(`group:${groupPrefix}`, true);
            }
        }
        if (!isGrouped) expandedGroups.set('Ungrouped', true);
        renderSessionGroups(false);
    }

    function setSidebarOpen(open) {
        document.body.classList.toggle('sidebar-open', open);
        sidebar?.classList.toggle('open', open);
        backdrop?.classList.toggle('visible', open);
        toggle?.setAttribute('aria-expanded', String(open));
        sidebar?.setAttribute('aria-hidden', String(!open));
        if (open) {
            if (sidebarDataReady) {
                expandCurrentSessionPath();
                requestAnimationFrame(() => scrollCurrentIntoView(byId('session-list')));
            } else {
                sidebarOpenNeedsCurrentReveal = true;
            }
        }
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
