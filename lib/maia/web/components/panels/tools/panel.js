/* Tools panel behavior. */
(() => {
    'use strict';

    const byId = (id) => document.getElementById(id);
    const api = (...args) => window.maiaApi.request(...args);
    const jsonOptions = (body) => ({
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
    });
    let loaded = false;

    function setStatus(message, isError = false) {
        const node = byId('tools-status');
        if (!node) return;
        node.textContent = message;
        node.classList.toggle('error', isError);
    }

    function makeButton(label, title, handler) {
        const button = document.createElement('button');
        button.type = 'button';
        button.textContent = label;
        button.title = title;
        button.setAttribute('aria-label', title);
        button.className = 'small-action';
        button.addEventListener('click', handler);
        return button;
    }

    function renderPatterns(list, patterns, onRemove) {
        list.replaceChildren();
        for (const pattern of patterns) {
            const item = document.createElement('li');
            const text = document.createElement('span');
            text.textContent = pattern;
            item.append(text, makeButton('×', `Remove ${pattern}`, () => onRemove(pattern)));
            list.appendChild(item);
        }
    }

    async function updateTool(action, pattern = '') {
        const options = pattern
            ? { method: 'POST', headers: { 'Content-Type': 'text/plain; charset=utf-8' }, body: pattern }
            : { method: 'POST' };
        try {
            await api(`/api/tool/${action}?scope=home`, options);
            loaded = false;
            await loadTools();
        } catch (error) { setStatus(error.message, true); }
    }

    async function addTool(pattern) {
        const input = byId('tool-pattern');
        const value = (pattern || input.value).trim();
        if (!value) return;
        await updateTool('append', value);
        if (input) input.value = '';
    }

    async function loadTools() {
        setStatus('Loading tools…');
        try {
            const result = await api('/api/tool/context?scope=home');
            byId('tools-scope').textContent = `Tool scope '${result.scope || 'home'}'`;
            renderPatterns(byId('tool-pattern-list'), result.patterns || [], (pattern) => updateTool('disable', pattern));
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
                const state = allowed
                    ? Object.assign(document.createElement('span'), { textContent: 'Yes' })
                    : makeButton('No', `Allow ${tool.name}`, () => addTool(pattern));
                item.append(label, effects, state);
                list.appendChild(item);
            }
            if (!list.children.length) {
                const empty = document.createElement('li');
                empty.textContent = 'No available tools.';
                list.appendChild(empty);
            }
            setStatus(result.patterns?.length ? '' : 'No tool patterns configured.');
            loaded = true;
        } catch (error) { setStatus(error.message, true); }
    }

    document.addEventListener('maia:panel-open', (event) => {
        if (event.detail?.id === 'tools' && !loaded) loadTools();
    });
    byId('tool-pattern-add')?.addEventListener('click', () => addTool());
    byId('tool-pattern')?.addEventListener('keydown', (event) => {
        if (event.key === 'Enter') { event.preventDefault(); addTool(); }
    });
    byId('tool-clear')?.addEventListener('click', () => updateTool('clear'));
    byId('tool-delete')?.addEventListener('click', () => updateTool('delete'));
    byId('tools-refresh')?.addEventListener('click', async () => {
        try {
            await api('/api/tool/context?scope=home', jsonOptions({ action: 'refresh', scope: 'home' }));
            loaded = false;
            await loadTools();
        } catch (error) { setStatus(error.message, true); }
    });
})();
