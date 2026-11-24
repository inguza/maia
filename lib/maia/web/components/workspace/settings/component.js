/* Workspace-scoped settings. */
(() => {
    'use strict';

    const root = document.querySelector('.workspace-settings-panel');
    if (!root || !window.maiaApi || !window.maiaUi) return;

    const form = root.querySelector('[data-workspace-settings-form]');
    const path = root.querySelector('#workspace-settings-path');
    const status = root.querySelector('[data-workspace-settings-status]');
    const save = root.querySelector('[data-workspace-settings-save]');
    const name = String(document.body?.dataset?.maiaWorkspace || '').trim();
    const endpoint = `/api/workspace/settings?name=${encodeURIComponent(name)}`;

    function applySettings(result, fallbackPath = '') {
        path.value = result.path || fallbackPath;
        const editable = result.pathEditable !== false;
        path.disabled = !editable;
        save.disabled = !editable;
        path.classList.toggle('outside-home', result.outsideHome === true && !editable);
        if (result.outsideHome === true && !editable) {
            setStatus('This workspace is outside MAIA HOME. Path changes are disabled by policy.');
        }
    }

    function setStatus(message, error = false) {
        window.maiaUi.setStatus(status, message, { error });
    }

    async function loadSettings() {
        window.maiaUi.setLoadingStatus(status, 'Loading workspace settings...');
        try {
            const result = await window.maiaApi.request(endpoint);
            applySettings(result);
            if (!(result.outsideHome === true && result.pathEditable === false)) setStatus('');
        } catch (error) {
            setStatus(error.message || 'Unable to load workspace settings.', true);
        }
    }

    form.addEventListener('submit', (event) => {
        event.preventDefault();
        const value = path.value.trim();
        if (!value) {
            setStatus('Enter a workspace directory.', true);
            path.focus();
            return;
        }

        void window.maiaUi.runBusy(save, 'Saving workspace settings...', async () => {
            window.maiaUi.setLoadingStatus(status, 'Saving workspace settings...');
            try {
                const result = await window.maiaApi.request(endpoint, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ path: value })
                });
                applySettings(result, value);
                setStatus('Workspace settings saved.');
            } catch (error) {
                setStatus(error.message || 'Unable to save workspace settings.', true);
            }
        });
    });

    void loadSettings();
})();
