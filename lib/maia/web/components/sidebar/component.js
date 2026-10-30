/* Navigation behavior owned by SidebarComponent. */
(() => {
    'use strict';

    const byId = (id) => document.getElementById(id);
    const api = (...args) => window.maiaApi.request(...args);
    const url = (path) => window.maiaApi.url(path);
    const data = { sessions: [], workspaces: [], profiles: [] };

    function setError(message) {
        const element = byId('home-error');
        if (!element) return;
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
        const wrapper = document.createElement('div');
        wrapper.className = 'sidebar-item-actions';
        const toggle = document.createElement('button');
        toggle.type = 'button';
        toggle.className = 'sidebar-item-actions-toggle';
        toggle.textContent = '\u2630';
        toggle.title = `Actions for ${name}`;
        toggle.setAttribute('aria-label', `Actions for ${name}`);
        toggle.setAttribute('aria-haspopup', 'menu');
        toggle.setAttribute('aria-expanded', 'false');
        const menu = document.createElement('div');
        menu.className = 'sidebar-item-menu';
        menu.setAttribute('role', 'menu');
        menu.hidden = true;
        actionMenuContexts.set(menu, { parent: wrapper, toggle });

        for (const action of actions) {
            const button = document.createElement('button');
            button.type = 'button';
            button.className = 'sidebar-action';
            button.textContent = `${action.icon} ${action.label}`;
            button.setAttribute('aria-label', action.label);
            button.setAttribute('role', 'menuitem');
            window.maiaUi.bindBusyClick(button, async () => {
                closeActionMenu(menu);
                await action.run();
            }, {
                busyText: `${action.label}...`,
                onError: (error) => setError(error.message)
            });
            menu.appendChild(button);
        }

        toggle.addEventListener('click', (event) => {
            event.stopPropagation();
            const shouldOpen = menu.hidden;
            closeAllActionMenus();
            if (!shouldOpen) return;
            menu.classList.add('sidebar-item-menu-floating');
            document.body.appendChild(menu);
            menu.hidden = false;
            toggle.setAttribute('aria-expanded', 'true');
            positionActionMenu(menu, toggle);
        });
        wrapper.append(toggle, menu);
        return wrapper;
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

    function renderNames(type) {
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
            link.href = type === 'session'
                ? url(`/session/${encodeURIComponent(name)}`)
                : url(`/${type}/${encodeURIComponent(name)}`);
            item.appendChild(link);

            if (type === 'session') {
                item.appendChild(createActionMenu(name, [
                    { icon: '\u2699\uFE0E', label: 'Settings', run: () => openSessionSettings(name) },
                    { icon: '\u270E', label: 'Rename', run: () => renameSession(name) },
                    { icon: '\u29C9', label: 'Copy', run: () => copySession(name) },
                    { icon: '\u00D7', label: 'Delete', run: () => deleteSession(name) }
                ]));
            } else {
                item.appendChild(createActionMenu(name, [
                    { icon: '\u2699\uFE0E', label: 'Settings', run: () => editResource(type, name) },
                    { icon: '\u00D7', label: 'Delete', run: () => deleteResource(type, name) }
                ]));
            }
            list.appendChild(item);
        }

        if (type === 'session') resizeSessionListToFit();
        placeholder.hidden = matches.length > 0;
        if (!matches.length) {
            placeholder.textContent = invalidRegex
                ? 'Invalid regular expression.'
                : query ? 'No matches.' : `No ${type}s found.`;
        }
        updateCreateButton(type, query, names);
    }

    function updateCreateButton(type, query, names) {
        const button = byId(`${type}-create`);
        if (button) button.hidden = !query || names.includes(query) || !validName(query);
    }

    async function loadSidebar() {
        for (const [id, message] of [
            ['session-list-placeholder', 'Loading sessions…'],
            ['workspace-list-placeholder', 'Loading workspaces…'],
            ['profile-list-placeholder', 'Loading profiles…']
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
            const sessions = await api('/api/session/list');
            const selectedSession = String(sessions.selected || '').trim();
            const settingsResponse = await fetch(url('/api/session/settings'), {
                headers: selectedSession ? { 'X-MAIA-Session': selectedSession } : {}
            });
            const settings = await settingsResponse.json();
            if (!settingsResponse.ok || !settings.ok) {
                throw new Error(settings.error || 'Unable to load workspaces and profiles.');
            }
            data.sessions = (sessions.sessions || []).map((item) => String(item.name || '')).filter(Boolean);
            data.workspaces = (settings.workspaces || []).map(String);
            data.profiles = (settings.profiles || []).map(String);
            for (const type of ['session', 'workspace', 'profile']) renderNames(type);
        } catch (error) {
            for (const id of ['session-list-placeholder', 'workspace-list-placeholder', 'profile-list-placeholder']) {
                const node = byId(id);
                if (node) { node.hidden = false; node.textContent = error.message; }
            }
        }
    }

    async function createResource(type, name, source = '') {
        const body = { name };
        if (type === 'workspace') {
            body.path = window.prompt('Workspace path relative to MAIA home:') || '';
            if (!body.path) return;
        } else if (type === 'profile') {
            body.description = window.prompt('Profile description (optional):') || '';
        } else if (source) {
            body.source = source;
        }
        const endpoint = type === 'session' ? '/api/session/create'
            : type === 'workspace' ? '/api/workspace/create' : '/api/profile/create?scope=home';
        await api(endpoint, {
            method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body)
        });
        if (type === 'session') {
            window.location.href = url(`/session/${encodeURIComponent(name)}`);
        } else {
            await loadSidebar();
        }
    }

    async function renameSession(oldName) {
        const name = window.prompt(`Rename session '${oldName}' to:`, oldName);
        if (!name || name === oldName) return;
        if (!validName(name)) { setError('Invalid session name.'); return; }
        try {
            await api('/api/session/rename', {
                method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ oldName, newName: name })
            });
            await loadSidebar();
        } catch (error) { setError(error.message); }
    }

    async function copySession(source) {
        const name = window.prompt(`Name for the copy of '${source}':`, `${source}-copy`);
        if (!name) return;
        if (!validName(name)) { setError('Invalid session name.'); return; }
        try { await createResource('session', name, source); }
        catch (error) { setError(error.message); }
    }

    async function deleteSession(name, button) {
        if (!window.confirm(`Permanently delete session '${name}' and its history? This cannot be undone.`)) return;
        setBusy(button, `Deleting session ${name}…`);
        try {
            await api('/api/session/delete', {
                method: 'POST', headers: { 'Content-Type': 'text/plain; charset=utf-8' }, body: name
            });
            await loadSidebar();
        } catch (error) { setError(error.message); }
        finally { clearBusy(button); }
    }

    async function deleteResource(type, name, button) {
        const message = type === 'workspace'
            ? `Delete workspace '${name}'? Its files will not be deleted.`
            : `Permanently delete profile '${name}'?`;
        if (!window.confirm(message)) return;
        setBusy(button, `Deleting ${type} ${name}…`);
        try {
            await api(type === 'workspace' ? '/api/workspace/delete' : '/api/profile/delete', {
                method: 'POST', headers: { 'Content-Type': 'text/plain; charset=utf-8' }, body: name
            });
            await loadSidebar();
        } catch (error) { setError(error.message); }
        finally { clearBusy(button); }
    }

    async function editResource(type, name) {
        const endpoint = `/api/${type}/settings?name=${encodeURIComponent(name)}`;
        try {
            const settings = await api(endpoint);
            const field = type === 'workspace' ? 'path' : 'description';
            const value = window.prompt(type === 'workspace' ? 'Workspace path relative to MAIA home:' : 'Profile description:', settings[field] || '');
            if (value === null) return;
            await api(endpoint, {
                method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ [field]: value })
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

    for (const type of ['session', 'workspace', 'profile']) {
        const form = byId(`${type}-search`);
        const input = byId(`${type}-search-input`);
        input?.addEventListener('input', () => renderNames(type));
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

    window.addEventListener('resize', resizeSessionListToFit);
    document.addEventListener('scroll', () => {
        document.querySelectorAll('.sidebar-item-menu-floating').forEach((menu) => {
            const context = actionMenuContexts.get(menu);
            if (context) positionActionMenu(menu, context.toggle);
        });
    }, true);
    document.addEventListener('click', (event) => {
        const target = event.target instanceof Element ? event.target : null;
        if (!target?.closest('.sidebar-item-actions, .sidebar-item-menu')) closeAllActionMenus();
    });
    document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape') closeAllActionMenus();
    });

    const sidebar = byId('sidebar');
    const toggle = byId('sidebar-toggle');
    const backdrop = byId('sidebar-backdrop');
    function setSidebarOpen(open) {
        document.body.classList.toggle('sidebar-open', open);
        sidebar?.classList.toggle('open', open);
        backdrop?.classList.toggle('visible', open);
        toggle?.setAttribute('aria-expanded', String(open));
        sidebar?.setAttribute('aria-hidden', String(!open));
    }
    toggle?.addEventListener('click', () => setSidebarOpen(!sidebar?.classList.contains('open')));
    byId('sidebar-close')?.addEventListener('click', () => setSidebarOpen(false));
    backdrop?.addEventListener('click', () => setSidebarOpen(false));
    document.addEventListener('keydown', (event) => { if (event.key === 'Escape') setSidebarOpen(false); });

    loadSidebar();
})();
