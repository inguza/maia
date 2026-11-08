/* Approvals panel behavior. */
(() => {
    'use strict';

    const byId = (id) => document.getElementById(id);
    function currentContextScope() {
        const context = document.body?.dataset || {};
        if (context.maiaProfile) return 'profile';
        if (context.maiaSession) return 'session';
        if (context.maiaWorkspace) return 'workspace';
        if (context.maiaHome) return 'home';
        return 'session';
    }

    const api = (path, ...args) => {
        const scopedPath = typeof path === 'string' && path.startsWith('/api/approval/')
            ? path.replace(/([?&])scope=[^&]*/, `$1scope=${encodeURIComponent(currentContextScope())}`)
            : path;
        return window.maiaApi.request(scopedPath, ...args);
    };
    let loaded = false;

    function setStatus(message, isError = false) {
        window.maiaUi.setStatus('approvals-status', message, { error: isError });
    }

    function setLoadingStatus(message) {
        window.maiaUi.setLoadingStatus('approvals-status', message);
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

    function renderRules(rules) {
        const list = byId('approval-rule-list');
        list.replaceChildren();
        for (const rule of rules) {
            const item = document.createElement('li');
            const text = document.createElement('span');
            text.textContent = rule;
            item.append(text, makeButton('\u00D7', `Remove ${rule}`, () => updateApproval('disable', rule)));
            list.appendChild(item);
        }
    }

    async function updateApproval(action, rule = '') {
        const options = rule
            ? { method: 'POST', headers: { 'Content-Type': 'text/plain; charset=utf-8' }, body: rule }
            : { method: 'POST' };
        try {
            await api(`/api/approval/${action}?scope=home`, options);
            loaded = false;
            await loadApprovals();
        } catch (error) {
            setStatus(error.message, true);
        }
    }

    async function addRule() {
        const input = byId('approval-rule');
        const rule = input.value.trim();
        if (!rule) return;
        await updateApproval('append', rule);
        input.value = '';
    }

    async function loadApprovals() {
        setLoadingStatus('Loading approvals…');
        try {
            const result = await api('/api/approval/context?scope=home');
            const effectiveScope = result.scope || 'default';
            const pageScope = result.targetScope || currentContextScope();
            const scopeLabel = byId('approvals-scope');
            scopeLabel.textContent = `Approval scope '${effectiveScope}'`;
            const displayedScope = scopeLabel.textContent.match(/^Approval scope '(.+)'$/)?.[1] || '';
            byId('approval-delete').hidden = displayedScope !== pageScope;
            const rules = Array.isArray(result.rules) ? result.rules : [];
            renderRules(rules);
            setStatus(rules.length > 0 ? '' : 'No approval rules configured.');
            loaded = true;
        } catch (error) {
            setStatus(error.message || 'Unable to load approval rules.', true);
        }
    }
    document.addEventListener('maia:panel-open', (event) => {
        if (event.detail?.id === 'approvals' && !loaded) void loadApprovals();
    });
    window.maiaUi.bindBusyClick(byId('approval-rule-add'), addRule, {
        busyText: 'Adding approval rule…',
        onError: (error) => setStatus(error.message, true)
    });
    byId('approval-rule')?.addEventListener('keydown', (event) => {
        if (event.key === 'Enter') {
            event.preventDefault();
            void addRule();
        }
    });
    window.maiaUi.bindBusyClick(byId('approval-clear'), () => updateApproval('clear'), {
        busyText: 'Clearing approval rules…',
        onError: (error) => setStatus(error.message, true)
    });
    window.maiaUi.bindBusyClick(byId('approval-delete'), () => updateApproval('delete'), {
        busyText: 'Deleting approval rules…',
        onError: (error) => setStatus(error.message, true)
    });
    window.maiaUi.bindBusyClick(byId('approvals-refresh'), loadApprovals, {
        busyText: 'Refreshing approvals…',
        onError: (error) => setStatus(error.message, true)
    });
})();
