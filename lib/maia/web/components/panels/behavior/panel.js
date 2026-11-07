/* Behavior panel: edits the system-type behavior for the current page scope. */
(() => {
    'use strict';

    const byId = (id) => document.getElementById(id);
    const source = byId('behavior-source');
    const text = byId('behavior-text');
    const save = byId('behavior-save');
    const reset = byId('behavior-reset');
    const status = byId('behavior-status');
    const endpoint = '/api/system/behavior';
    let loaded = false;
    let currentScope = 'session';

    function pageScope() {
        const context = document.body?.dataset || {};
        if (context.maiaSession) return 'session';
        if (context.maiaProfile) return 'profile';
        if (context.maiaWorkspace) return 'workspace';
        if (context.maiaHome) return 'home';
        return 'session';
    }

    function scopeLabel(scope) {
        return scope === 'default' ? 'the built-in default' : `the ${scope} scope`;
    }

    function setStatus(message, error = false) {
        window.maiaUi.setStatus(status, message, { error });
    }

    function setLoading(message) {
        window.maiaUi.setLoadingStatus(status, message);
    }

    function render(result) {
        currentScope = result.scope || pageScope();
        text.value = result.text || '';
        text.disabled = false;
        save.disabled = false;
        reset.hidden = !result.local;
        reset.textContent = 'Delete';
        const resetDescription = `Remove this ${currentScope} behavior version`;
        reset.title = resetDescription;
        reset.setAttribute('aria-label', resetDescription);

        if (result.local) {
            source.textContent = `Using behavior saved for ${currentScope}.`;
        } else {
            const sourceScope = result.sourceScope || 'default';
            source.textContent = `Using behavior from ${scopeLabel(sourceScope)}. Saving here creates a ${currentScope}-specific version.`;
        }
        loaded = true;
    }

    async function loadBehavior() {
        setLoading('Loading behavior…');
        try {
            render(await window.maiaApi.request(endpoint));
            setStatus('');
        } catch (error) {
            setStatus(error.message || 'Unable to load behavior.', true);
        }
    }

    async function saveBehavior() {
        setLoading('Saving behavior…');
        const result = await window.maiaApi.request(endpoint, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ action: 'save', text: text.value })
        });
        render(result);
        setStatus(`Saved behavior for ${currentScope}.`);
    }

    async function removeBehavior() {
        setLoading('Removing behavior…');
        const result = await window.maiaApi.request(endpoint, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ action: 'reset' })
        });
        render(result);
        const sourceScope = result.sourceScope || 'default';
        setStatus(`Now using behavior from ${scopeLabel(sourceScope)}.`);
    }

    document.addEventListener('maia:panel-open', (event) => {
        if (event.detail?.id === 'behavior' && !loaded) {
            void loadBehavior();
        }
    });

    window.maiaUi.bindBusyClick(save, saveBehavior, {
        busyText: 'Saving behavior…',
        onError: (error) => setStatus(error.message || 'Unable to save behavior.', true)
    });
    window.maiaUi.bindBusyClick(reset, removeBehavior, {
        busyText: 'Removing behavior…',
        onError: (error) => setStatus(error.message || 'Unable to remove behavior.', true)
    });
})();
