/* Skills panel behavior. */
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
        window.maiaUi.setStatus('skills-status', message, { error: isError });
    }

    function setLoadingStatus(message) {
        window.maiaUi.setLoadingStatus('skills-status', message);
    }

    function makeButton(label, title, handler) {
        const button = document.createElement('button');
        button.type = 'button';
        button.textContent = label;
        button.title = title;
        button.setAttribute('aria-label', title);
        button.className = 'small-action';
        window.maiaUi.bindBusyClick(button, handler, {
            busyText: title,
            onError: (error) => setStatus(error.message, true)
        });
        return button;
    }

    function renderPatterns(list, patterns, onRemove) {
        list.replaceChildren();
        for (const pattern of patterns) {
            const item = document.createElement('li');
            const text = document.createElement('span');
            text.textContent = pattern;
            item.append(text, makeButton('\u00D7', `Remove ${pattern}`, () => onRemove(pattern)));
            list.appendChild(item);
        }
    }

    async function updateSkill(action, pattern = '') {
        try {
            await api('/api/skill/context?scope=home', jsonOptions({ action, ...(pattern ? { pattern } : {}) }));
            loaded = false;
            await loadSkills();
        } catch (error) { setStatus(error.message, true); }
    }

    async function updateMemory(name, remember) {
        try {
            await api('/api/skill/context?scope=home', jsonOptions({ action: 'memory', name, remember }));
            loaded = false;
            await loadSkills();
        } catch (error) { setStatus(error.message, true); }
    }

    async function addSkill(pattern) {
        const input = byId('skill-pattern');
        const value = (pattern || input.value).trim();
        if (!value) return;
        await updateSkill('append', value);
        if (input) input.value = '';
    }

    async function loadSkills() {
        setLoadingStatus('Loading skills\u2026');
        try {
            const result = await api('/api/skill/context?scope=home');
            byId('skills-scope').textContent = `Skill scope '${result.scope || 'home'}'`;
            renderPatterns(byId('skill-pattern-list'), result.patterns || [], (pattern) => updateSkill('disable', pattern));
            const list = byId('available-skills-list');
            const heading = list.querySelector('.available-resource-heading');
            list.replaceChildren();
            if (heading) list.appendChild(heading);
            for (const skill of result.skills || []) {
                const item = document.createElement('li');
                const label = document.createElement('span');
                label.textContent = skill.description ? `${skill.name} — ${skill.description}` : skill.name;
                const allowed = skill.allowed
                    ? Object.assign(document.createElement('span'), { textContent: 'Yes' })
                    : makeButton('No', `Allow ${skill.name}`, () => addSkill(skill.name));
                const memory = makeButton(skill.memory ? 'Yes' : 'No',
                    skill.memory ? `Remove ${skill.name} from memory` : `Load ${skill.name} into memory`,
                    () => updateMemory(skill.name, !skill.memory));
                memory.disabled = !skill.allowed;
                item.append(label, allowed, memory);
                list.appendChild(item);
            }
            if (list.children.length === (heading ? 1 : 0)) {
                const empty = document.createElement('li');
                empty.textContent = 'No available skills.';
                list.appendChild(empty);
            }
            setStatus(result.patterns?.length ? '' : 'No skill patterns configured.');
            loaded = true;
        } catch (error) { setStatus(error.message, true); }
    }

    document.addEventListener('maia:panel-open', (event) => {
        if (event.detail?.id === 'skills' && !loaded) loadSkills();
    });
    window.maiaUi.bindBusyClick(byId('skill-pattern-add'), () => addSkill(), {
        busyText: 'Adding skill pattern\u2026',
        onError: (error) => setStatus(error.message, true)
    });
    byId('skill-pattern')?.addEventListener('keydown', (event) => {
        if (event.key === 'Enter') { event.preventDefault(); addSkill(); }
    });
    window.maiaUi.bindBusyClick(byId('skill-clear'), () => updateSkill('clear'), {
        busyText: 'Clearing skill patterns\u2026',
        onError: (error) => setStatus(error.message, true)
    });
    window.maiaUi.bindBusyClick(byId('skill-delete'), () => updateSkill('delete'), {
        busyText: 'Deleting skill patterns\u2026',
        onError: (error) => setStatus(error.message, true)
    });
    window.maiaUi.bindBusyClick(byId('skills-refresh'), async () => {
        await api('/api/skill/context?scope=home', jsonOptions({ action: 'refresh' }));
        loaded = false;
        await loadSkills();
    }, {
        busyText: 'Refreshing skills\u2026',
        onError: (error) => setStatus(error.message, true)
    });
})();
