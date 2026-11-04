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

    function setStatus(message, error = false) {
        window.maiaUi.setStatus(status, message, { error });
    }

    async function loadSettings() {
        window.maiaUi.setLoadingStatus(status, 'Loading workspace settings...');
        try {
            const result = await window.maiaApi.request(endpoint);
            path.value = result.path || '';
            setStatus('');
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
                path.value = result.path || value;
                setStatus('Workspace settings saved.');
            } catch (error) {
                setStatus(error.message || 'Unable to save workspace settings.', true);
            }
        });
    });

    void loadSettings();
})();
