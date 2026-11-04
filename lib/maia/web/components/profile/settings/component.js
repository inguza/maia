/* Profile settings behavior owned by ProfileSettingsComponent. */
(() => {
    'use strict';

    const byId = (id) => document.getElementById(id);
    const toggle = byId('profile-settings-toggle');
    const dialog = byId('profile-settings-dialog');
    const form = byId('profile-settings-form');
    const description = byId('profile-settings-description');
    const scope = byId('profile-settings-scope');
    const status = byId('profile-settings-status');
    const save = byId('profile-settings-save');
    const name = document.body?.dataset?.maiaProfile || '';
    const endpoint = `/api/profile/settings?name=${encodeURIComponent(name)}`;
    let loaded = false;

    async function loadSettings() {
        window.maiaUi.setLoadingStatus(status, 'Loading profile settings…');
        try {
            const result = await window.maiaApi.request(endpoint);
            description.value = result.description || '';
            scope.textContent = result.scope ? `Scope: ${result.scope}` : '';
            status.textContent = '';
            loaded = true;
        } catch (error) {
            window.maiaUi.setStatus(status, error.message || 'Unable to load profile settings.', { error: true });
        }
    }

    toggle?.addEventListener('click', async () => {
        if (!dialog) return;
        if (!dialog.open) {
            dialog.showModal();
            if (!loaded) await loadSettings();
        }
    });

    form?.addEventListener('submit', async (event) => {
        if (event.submitter?.value !== 'save') return;
        event.preventDefault();
        await window.maiaUi.runBusy(save, 'Saving profile…', async () => {
            window.maiaUi.setLoadingStatus(status, 'Saving profile…');
            try {
                const result = await window.maiaApi.request(endpoint, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ description: description.value })
                });
                description.value = result.description || '';
                scope.textContent = result.scope ? `Scope: ${result.scope}` : '';
                window.maiaUi.setStatus(status, 'Saved.');
                loaded = true;
            } catch (error) {
                window.maiaUi.setStatus(status, error.message || 'Unable to save profile settings.', { error: true });
            }
        });
    });
})();
