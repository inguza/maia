/* Home page behavior: shared navigation and home-scoped panels. */
(() => {
    'use strict';

    const basePath = String(window.MAIA_BASE_PATH || '').replace(/\/$/, '');
    const url = (path) => `${basePath}${path}`;
    const byId = (id) => document.getElementById(id);
    const loaded = { credentials: false, skills: false, tools: false };

    async function api(path, options = {}) {
        const headers = new Headers(options.headers || {});
        headers.set('X-MAIA-Home', 'home');
        const response = await fetch(url(path), { ...options, headers });
        let result;
        try {
            result = await response.json();
        } catch (_) {
            throw new Error(`The server returned an invalid response (${response.status}).`);
        }
        if (!response.ok || result?.ok === false) {
            throw new Error(result?.error || `Request failed (${response.status}).`);
        }
        return result;
    }

    const jsonOptions = (body) => ({
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
    });

    function setStatus(id, message, isError = false) {
        const element = byId(id);
        if (!element) return;
        element.textContent = message;
        element.classList.toggle('error', isError);
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

    function renderNames(listId, placeholderId, names, type) {
        const list = byId(listId);
        const placeholder = byId(placeholderId);
        if (!list || !placeholder) return;
        const search = byId(`${type}-search-input`);
        const query = search?.value.trim() || '';
        let matches = names;
        if (query) {
            try {
                const expression = new RegExp(query, 'i');
                matches = names.filter((name) => expression.test(name));
            } catch (_) {
                matches = [];
                placeholder.textContent = 'Invalid regular expression.';
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
            if (type !== 'session') {
                item.appendChild(makeButton('×', `Delete ${type} ${name}`, async () => {
                    if (!window.confirm(`Permanently delete ${type} “${name}”?`)) return;
                    const endpoint = type === 'workspace' ? '/api/workspace/delete' : '/api/profile/delete';
                    try {
                        await api(endpoint, { method: 'POST', headers: { 'Content-Type': 'text/plain; charset=utf-8' }, body: name });
                        await loadSidebar();
                    } catch (error) {
                        setStatus('home-error', error.message, true);
                    }
                }, 'small-action'));
            }
            list.appendChild(item);
        }
        if (matches.length > 0) {
            placeholder.hidden = true;
        } else {
            placeholder.hidden = false;
            if (!query || placeholder.textContent !== 'Invalid regular expression.') {
                placeholder.textContent = query ? 'No matches.' : `No ${type}s found.`;
            }
        }
    }

    let sidebarData = { sessions: [], workspaces: [], profiles: [] };
    async function loadSidebar() {
        for (const [id, message] of [
            ['session-list-placeholder', 'Loading sessions...'],
            ['workspace-list-placeholder', 'Loading workspaces...'],
            ['profile-list-placeholder', 'Loading profiles...']
        ]) {
            const node = byId(id);
            if (node) { node.hidden = false; node.textContent = message; }
        }
        try {
            const [sessions, settings] = await Promise.all([
                api('/api/session/list'),
                api('/api/session/settings')
            ]);
            sidebarData = {
                sessions: (sessions.sessions || []).map((item) => String(item.name || '')).filter(Boolean),
                workspaces: (settings.workspaces || []).map(String),
                profiles: (settings.profiles || []).map(String)
            };
            renderNames('session-list', 'session-list-placeholder', sidebarData.sessions, 'session');
            renderNames('workspace-list', 'workspace-list-placeholder', sidebarData.workspaces, 'workspace');
            renderNames('profile-list', 'profile-list-placeholder', sidebarData.profiles, 'profile');
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
        await api(endpoint, jsonOptions(body));
        if (type === 'session') {
            window.location.href = url(`/session/${encodeURIComponent(name)}`);
            return;
        }
        await loadSidebar();
    }

    for (const type of ['session', 'workspace', 'profile']) {
        const form = byId(`${type}-search`);
        const input = byId(`${type}-search-input`);
        input?.addEventListener('input', () => renderNames(
            `${type}-list`, `${type}-list-placeholder`, sidebarData[`${type}s`], type
        ));
        form?.addEventListener('submit', async (event) => {
            event.preventDefault();
            const name = input?.value.trim() || '';
            if (!name) return;
            const names = sidebarData[`${type}s`] || [];
            if (names.includes(name)) {
                window.location.href = type === 'session'
                    ? url(`/session/${encodeURIComponent(name)}`)
                    : url(`/${type}/${encodeURIComponent(name)}`);
                return;
            }
            if (!/^[A-Za-z0-9_.%+\-]+$/.test(name)) {
                setStatus('home-error', `Invalid ${type} name.`, true);
                return;
            }
            try {
                await createResource(type, name);
            } catch (error) {
                setStatus('home-error', error.message, true);
            }
        });
    }

    const sidebar = byId('sidebar');
    const sidebarToggle = byId('sidebar-toggle');
    const sidebarBackdrop = byId('sidebar-backdrop');
    function setSidebarOpen(open) {
        sidebar?.classList.toggle('open', open);
        sidebarBackdrop?.classList.toggle('visible', open);
        sidebarToggle?.setAttribute('aria-expanded', String(open));
        sidebar?.setAttribute('aria-hidden', String(!open));
    }
    sidebarToggle?.addEventListener('click', () => setSidebarOpen(!sidebar?.classList.contains('open')));
    byId('sidebar-close')?.addEventListener('click', () => setSidebarOpen(false));
    sidebarBackdrop?.addEventListener('click', () => setSidebarOpen(false));
    document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape') setSidebarOpen(false);
    });

    document.querySelectorAll('[data-expandable-panel]').forEach((panel) => {
        const toggle = panel.querySelector('.panel-toggle');
        const content = panel.querySelector('.panel-content');
        toggle?.addEventListener('click', async () => {
            const expanded = content.hidden;
            content.hidden = !expanded;
            toggle.setAttribute('aria-expanded', String(expanded));
            const arrow = toggle.querySelector('[aria-hidden="true"]');
            if (arrow) arrow.textContent = expanded ? '▾' : '▸';
            if (!expanded) return;
            if (panel.id === 'credentials' && !loaded.credentials) await loadCredentials();
            if (panel.id === 'skills' && !loaded.skills) await loadSkills();
            if (panel.id === 'tools' && !loaded.tools) await loadTools();
        });
    });

    async function loadCredentials() {
        setStatus('credentials-status', 'Loading credentials...');
        try {
            const result = await api('/api/auth/context');
            const list = byId('credential-list');
            list.replaceChildren();
            for (const credential of result.credentials || []) {
                const item = document.createElement('li');
                const value = document.createElement('span');
                value.textContent = credential.salt
                    ? `${credential.name}:${String(credential.salt).slice(0, 4)}`
                    : credential.name;
                const remove = makeButton('×', `Delete credential ${credential.name}`, async () => {
                    if (!window.confirm(`Delete credential “${credential.name}”? Existing links using it will stop working.`)) return;
                    try {
                        await api('/api/auth/context', jsonOptions({ action: 'delete', identifier: credential.identifier }));
                        loaded.credentials = false;
                        await loadCredentials();
                    } catch (error) { setStatus('credentials-status', error.message, true); }
                }, 'small-action');
                item.append(value, remove);
                list.appendChild(item);
            }
            setStatus('credentials-status', result.credentials?.length ? '' : 'No credentials configured.');
            loaded.credentials = true;
        } catch (error) { setStatus('credentials-status', error.message, true); }
    }

    byId('credential-create')?.addEventListener('click', async () => {
        const button = byId('credential-create');
        const name = byId('credential-name').value.trim();
        if (name && !/^[A-Za-z0-9_-]+$/.test(name)) {
            setStatus('credentials-status', 'Use only letters, digits, underscore, and hyphen.', true);
            return;
        }
        button.disabled = true;
        setStatus('credentials-status', 'Creating credential...');
        try {
            const result = await api('/api/auth/context', jsonOptions({ action: 'create', name }));
            loaded.credentials = false;
            await loadCredentials();
            const status = byId('credentials-status');
            status.replaceChildren();
            const message = document.createElement('span');
            message.textContent = 'Credential created. ';
            status.appendChild(message);
            if (result.url) {
                const link = document.createElement('a');
                link.href = result.url;
                link.textContent = 'Open authentication URL';
                link.target = '_blank';
                link.rel = 'noopener noreferrer';
                status.appendChild(link);
            }
            if (result.qrUrl) {
                const link = document.createElement('a');
                link.href = result.qrUrl;
                link.textContent = ' QR code';
                link.target = '_blank';
                link.rel = 'noopener noreferrer';
                status.appendChild(link);
            }
            byId('credential-name').value = '';
        } catch (error) { setStatus('credentials-status', error.message, true); }
        finally { button.disabled = false; }
    });

    function renderPatterns(list, patterns, removeHandler) {
        list.replaceChildren();
        for (const pattern of patterns) {
            const item = document.createElement('li');
            const text = document.createElement('span');
            text.textContent = pattern;
            item.append(text, makeButton('×', `Remove ${pattern}`, (event) => removeHandler(pattern, event.currentTarget), 'small-action'));
            list.appendChild(item);
        }
    }

    async function loadSkills() {
        setStatus('skills-status', 'Loading skills...');
        try {
            const result = await api('/api/skill/context?scope=home');
            byId('skills-scope').textContent = `Skill scope '${result.scope || 'home'}'`;
            renderPatterns(byId('skill-pattern-list'), result.patterns || [], updateSkill);
            const list = byId('available-skills-list');
            list.replaceChildren();
            for (const skill of result.skills || []) {
                const item = document.createElement('li');
                const label = document.createElement('span');
                label.textContent = skill.description ? `${skill.name} — ${skill.description}` : skill.name;
                const allowed = skill.allowed
                    ? document.createElement('span')
                    : makeButton('No', `Allow ${skill.name}`, () => addSkill(skill.name));
                if (skill.allowed) allowed.textContent = 'Yes';
                const memory = makeButton(skill.memory ? 'Yes' : 'No',
                    skill.memory ? `Remove ${skill.name} from memory` : `Load ${skill.name} into memory`,
                    () => updateSkillMemory(skill.name, !skill.memory));
                memory.disabled = !skill.allowed;
                item.append(label, allowed, memory);
                list.appendChild(item);
            }
            if (!list.children.length) {
                const empty = document.createElement('li'); empty.textContent = 'No available skills.'; list.appendChild(empty);
            }
            setStatus('skills-status', result.patterns?.length ? '' : 'No skill patterns configured.');
            loaded.skills = true;
        } catch (error) { setStatus('skills-status', error.message, true); loaded.skills = false; }
    }

    async function updateSkill(action, pattern = '') {
        try {
            await api('/api/skill/context?scope=home', jsonOptions({ action, ...(pattern ? { pattern } : {}) }));
            loaded.skills = false; await loadSkills();
        } catch (error) { setStatus('skills-status', error.message, true); }
    }
    async function addSkill(pattern) {
        const input = byId('skill-pattern');
        const value = (pattern || input.value).trim();
        if (!value) return;
        await updateSkill('append', value);
        if (input) input.value = '';
    }
    async function updateSkillMemory(name, remember) {
        try {
            await api('/api/skill/context?scope=home', jsonOptions({ action: 'memory', name, remember }));
            loaded.skills = false; await loadSkills();
        } catch (error) { setStatus('skills-status', error.message, true); }
    }
    byId('skill-pattern-add')?.addEventListener('click', () => addSkill());
    byId('skill-pattern')?.addEventListener('keydown', (event) => {
        if (event.key === 'Enter') { event.preventDefault(); addSkill(); }
    });
    byId('skill-clear')?.addEventListener('click', () => updateSkill('clear'));
    byId('skill-delete')?.addEventListener('click', () => updateSkill('delete'));
    byId('skills-refresh')?.addEventListener('click', async () => {
        try { await api('/api/skill/context?scope=home', jsonOptions({ action: 'refresh' })); loaded.skills = false; await loadSkills(); }
        catch (error) { setStatus('skills-status', error.message, true); }
    });

    async function loadTools() {
        setStatus('tools-status', 'Loading tools...');
        try {
            const result = await api('/api/tool/context?scope=home');
            byId('tools-scope').textContent = `Tool scope '${result.scope || 'home'}'`;
            renderPatterns(byId('tool-pattern-list'), result.patterns || [], updateTool);
            const list = byId('available-tools-list');
            list.replaceChildren();
            for (const tool of result.tools || []) {
                const item = document.createElement('li');
                const label = document.createElement('span');
                label.textContent = tool.description ? `${tool.name} — ${tool.description}` : tool.name;
                const effects = document.createElement('span');
                effects.textContent = (tool.effects || []).join(', ') || '—';
                const pattern = tool.effects?.length ? `${tool.name}:${tool.effects.join('+')}` : tool.name;
                const allowed = tool.allowed || (result.patterns || []).includes(pattern) || (result.patterns || []).includes(tool.name);
                const state = allowed ? document.createElement('span') : makeButton('No', `Allow ${tool.name}`, () => addTool(pattern));
                if (allowed) state.textContent = 'Yes';
                item.append(label, effects, state);
                list.appendChild(item);
            }
            if (!list.children.length) {
                const empty = document.createElement('li'); empty.textContent = 'No available tools.'; list.appendChild(empty);
            }
            setStatus('tools-status', result.patterns?.length ? '' : 'No tool patterns configured.');
            loaded.tools = true;
        } catch (error) { setStatus('tools-status', error.message, true); loaded.tools = false; }
    }

    async function updateTool(action, pattern = '') {
        const body = pattern ? { method: 'POST', headers: { 'Content-Type': 'text/plain; charset=utf-8' }, body: pattern } : { method: 'POST' };
        try {
            await api(`/api/tool/${action}?scope=home`, body);
            loaded.tools = false; await loadTools();
        } catch (error) { setStatus('tools-status', error.message, true); }
    }
    async function addTool(pattern) {
        const input = byId('tool-pattern');
        const value = (pattern || input.value).trim();
        if (!value) return;
        await updateTool('append', value);
        if (input) input.value = '';
    }
    byId('tool-pattern-add')?.addEventListener('click', () => addTool());
    byId('tool-pattern')?.addEventListener('keydown', (event) => {
        if (event.key === 'Enter') { event.preventDefault(); addTool(); }
    });
    byId('tool-clear')?.addEventListener('click', () => updateTool('clear'));
    byId('tool-delete')?.addEventListener('click', () => updateTool('delete'));
    byId('tools-refresh')?.addEventListener('click', async () => {
        try { await api('/api/tool/context?scope=home', jsonOptions({ action: 'refresh', scope: 'home' })); loaded.tools = false; await loadTools(); }
        catch (error) { setStatus('tools-status', error.message, true); }
    });

    loadSidebar();
})();
