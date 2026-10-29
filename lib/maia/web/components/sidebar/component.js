/* Navigation behavior owned by SidebarComponent. */
(() => {
    'use strict';

    const byId = (id) => document.getElementById(id);
    const api = (...args) => window.maiaApi.request(...args);

    function setError(message) {
        const element = byId('home-error');
        if (!element) return;
        element.textContent = message;
        element.hidden = !message;
    }

    function makeButton(label, title, handler, className = '') {
        const button = document.createElement('button');
        button.type = 'button';
        button.textContent = label;
        button.title = title;
        button.setAttribute('aria-label', title);
        if (className) button.className = className;
        button.addEventListener('click', handler);
        return button;
    }

    let data = { sessions: [], workspaces: [], profiles: [] };

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
                ? window.maiaApi.url(`/session/${encodeURIComponent(name)}`)
                : window.maiaApi.url(`/${type}/${encodeURIComponent(name)}`);
            item.appendChild(link);

            if (type !== 'session') {
                item.appendChild(makeButton('×', `Delete ${type} ${name}`, async () => {
                    if (!window.confirm(`Permanently delete ${type} “${name}”?`)) return;
                    const endpoint = type === 'workspace'
                        ? '/api/workspace/delete'
                        : '/api/profile/delete';
                    try {
                        await api(endpoint, {
                            method: 'POST',
                            headers: { 'Content-Type': 'text/plain; charset=utf-8' },
                            body: name
                        });
                        await loadSidebar();
                    } catch (error) {
                        setError(error.message);
                    }
                }, 'small-action'));
            }
            list.appendChild(item);
        }

        placeholder.hidden = matches.length > 0;
        if (matches.length === 0) {
            placeholder.textContent = invalidRegex
                ? 'Invalid regular expression.'
                : query ? 'No matches.' : `No ${type}s found.`;
        }
    }

    async function loadSidebar() {
        for (const [id, message] of [
            ['session-list-placeholder', 'Loading sessions…'],
            ['workspace-list-placeholder', 'Loading workspaces…'],
            ['profile-list-placeholder', 'Loading profiles…']
        ]) {
            const node = byId(id);
            if (node) { node.hidden = false; node.textContent = message; }
        }
        try {
            const [sessions, settings] = await Promise.all([
                api('/api/session/list'),
                api('/api/session/settings')
            ]);
            data = {
                sessions: (sessions.sessions || []).map((item) => String(item.name || '')).filter(Boolean),
                workspaces: (settings.workspaces || []).map(String),
                profiles: (settings.profiles || []).map(String)
            };
            for (const type of ['session', 'workspace', 'profile']) renderNames(type);
        } catch (error) {
            for (const id of ['session-list-placeholder', 'workspace-list-placeholder', 'profile-list-placeholder']) {
                const node = byId(id);
                if (node) { node.hidden = false; node.textContent = error.message; }
            }
        }
    }

    async function createResource(type, name) {
        const body = { name };
        if (type === 'workspace') {
            body.path = window.prompt('Workspace filesystem path:') || '';
            if (!body.path) return;
        } else if (type === 'profile') {
            body.description = window.prompt('Profile description (optional):') || '';
        }
        const endpoint = type === 'session' ? '/api/session/create'
            : type === 'workspace' ? '/api/workspace/create' : '/api/profile/create?scope=home';
        await api(endpoint, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body)
        });
        if (type === 'session') {
            window.location.href = window.maiaApi.url(`/session/${encodeURIComponent(name)}`);
            return;
        }
        await loadSidebar();
    }

    for (const type of ['session', 'workspace', 'profile']) {
        const form = byId(`${type}-search`);
        const input = byId(`${type}-search-input`);
        input?.addEventListener('input', () => renderNames(type));
        form?.addEventListener('submit', async (event) => {
            event.preventDefault();
            const name = input?.value.trim() || '';
            if (!name) return;
            const names = data[`${type}s`] || [];
            if (names.includes(name)) {
                window.location.href = type === 'session'
                    ? window.maiaApi.url(`/session/${encodeURIComponent(name)}`)
                    : window.maiaApi.url(`/${type}/${encodeURIComponent(name)}`);
                return;
            }
            if (!/^[A-Za-z0-9_.%+\-]+$/.test(name)) {
                setError(`Invalid ${type} name.`);
                return;
            }
            try { await createResource(type, name); }
            catch (error) { setError(error.message); }
        });
    }

    const sidebar = byId('sidebar');
    const toggle = byId('sidebar-toggle');
    const backdrop = byId('sidebar-backdrop');
    function setSidebarOpen(open) {
        sidebar?.classList.toggle('open', open);
        backdrop?.classList.toggle('visible', open);
        toggle?.setAttribute('aria-expanded', String(open));
        sidebar?.setAttribute('aria-hidden', String(!open));
    }
    toggle?.addEventListener('click', () => setSidebarOpen(!sidebar?.classList.contains('open')));
    byId('sidebar-close')?.addEventListener('click', () => setSidebarOpen(false));
    backdrop?.addEventListener('click', () => setSidebarOpen(false));
    document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape') setSidebarOpen(false);
    });

    loadSidebar();
})();
