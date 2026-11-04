/* Profile management for the current home or workspace scope. */
(() => {
    'use strict';

    const root = document.querySelector('[data-profiles-manager]');
    if (!root || !window.maiaApi || !window.maiaUi) return;

    const scope = String(root.dataset.scope || '');
    const list = root.querySelector('[data-profiles-list]');
    const status = root.querySelector('[data-profiles-status]');
    const createForm = root.querySelector('[data-profile-create-form]');
    const createButton = root.querySelector('[data-profile-create]');
    const dialog = root.querySelector('[data-profile-settings-dialog]');
    const settingsForm = root.querySelector('[data-profile-settings-form]');
    const settingsTitle = root.querySelector('[data-profile-settings-title]');
    const settingsDescription = root.querySelector('#profiles-settings-description');
    const settingsScope = root.querySelector('[data-profile-settings-scope]');
    const settingsStatus = root.querySelector('[data-profile-settings-status]');
    const settingsSave = root.querySelector('[data-profile-settings-save]');
    let settingsName = '';

    function setStatus(message, error = false) {
        window.maiaUi.setStatus(status, message, { error });
    }

    function validName(name) {
        return /^[A-Za-z0-9_.%+\-]+$/.test(name);
    }

    function renderProfiles(profiles) {
        list.replaceChildren();
        if (!profiles.length) {
            const empty = document.createElement('li');
            empty.className = 'profiles-empty';
            empty.textContent = 'No profiles in this scope.';
            list.appendChild(empty);
            return;
        }

        for (const name of profiles) {
            const item = document.createElement('li');
            const label = document.createElement('a');
            label.className = 'profile-name';
            label.textContent = name;
            const workspace = String(root.dataset.workspace || '');
            const profilePath = scope === 'workspace'
                ? `/workspace/${encodeURIComponent(workspace)}/profiles/${encodeURIComponent(name)}`
                : `/profiles/${encodeURIComponent(name)}`;
            label.href = window.maiaApi.url(profilePath);

            const actions = document.createElement('span');
            actions.className = 'profile-actions';
            const settings = document.createElement('button');
            settings.type = 'button';
            settings.textContent = 'Settings';
            settings.setAttribute('aria-label', `Settings for profile ${name}`);
            settings.addEventListener('click', () => { void openSettings(name); });

            const remove = document.createElement('button');
            remove.type = 'button';
            remove.textContent = 'Delete';
            remove.setAttribute('aria-label', `Delete profile ${name}`);
            remove.addEventListener('click', () => { void deleteProfile(name, remove); });

            actions.append(settings, remove);
            item.append(label, actions);
            list.appendChild(item);
        }
    }

    async function loadProfiles() {
        window.maiaUi.setLoadingStatus(status, 'Loading profiles...');
        try {
            const result = await window.maiaApi.request('/api/session/settings');
            const profiles = Array.isArray(result.profiles)
                ? result.profiles.map(String).filter(Boolean)
                : [];
            renderProfiles(profiles);
            setStatus('');
        } catch (error) {
            list.replaceChildren();
            setStatus(error.message || 'Unable to load profiles.', true);
        }
    }

    async function openSettings(name) {
        settingsName = name;
        settingsTitle.textContent = `Profile settings: ${name}`;
        settingsDescription.value = '';
        settingsScope.textContent = '';
        window.maiaUi.setLoadingStatus(settingsStatus, 'Loading profile settings...');
        dialog.showModal();
        try {
            const result = await window.maiaApi.request(`/api/profile/settings?name=${encodeURIComponent(name)}`);
            settingsDescription.value = result.description || '';
            settingsScope.textContent = result.scope ? `Scope: ${result.scope}` : '';
            window.maiaUi.setStatus(settingsStatus, '');
        } catch (error) {
            window.maiaUi.setStatus(settingsStatus, error.message || 'Unable to load profile settings.', { error: true });
        }
    }

    async function deleteProfile(name, button) {
        if (!window.confirm(`Permanently delete profile '${name}'?`)) return;
        try {
            await window.maiaUi.runBusy(button, 'Deleting profile...', async () => {
                await window.maiaApi.request('/api/profile/delete', {
                    method: 'POST',
                    headers: { 'Content-Type': 'text/plain; charset=utf-8' },
                    body: name
                });
                await loadProfiles();
                setStatus(`Deleted profile '${name}'.`);
            });
        } catch (error) {
            setStatus(error.message || 'Unable to delete profile.', true);
        }
    }

    createForm.addEventListener('submit', async (event) => {
        event.preventDefault();
        const formData = new FormData(createForm);
        const name = String(formData.get('name') || '').trim();
        const description = String(formData.get('description') || '').trim();
        if (!validName(name)) {
            setStatus('Enter a valid profile name.', true);
            return;
        }

        try {
            await window.maiaUi.runBusy(createButton, 'Creating profile...', async () => {
                await window.maiaApi.request(`/api/profile/create?scope=${encodeURIComponent(scope)}`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ name, description })
                });
                createForm.reset();
                await loadProfiles();
                setStatus(`Created profile '${name}'.`);
            });
        } catch (error) {
            setStatus(error.message || 'Unable to create profile.', true);
        }
    });

    settingsForm.addEventListener('submit', async (event) => {
        event.preventDefault();
        if (!settingsName) return;
        try {
            await window.maiaUi.runBusy(settingsSave, 'Saving profile...', async () => {
                window.maiaUi.setLoadingStatus(settingsStatus, 'Saving profile settings...');
                const result = await window.maiaApi.request(
                    `/api/profile/settings?name=${encodeURIComponent(settingsName)}`,
                    {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ description: settingsDescription.value })
                    }
                );
                settingsDescription.value = result.description || '';
                settingsScope.textContent = result.scope ? `Scope: ${result.scope}` : '';
                window.maiaUi.setStatus(settingsStatus, 'Saved.');
            });
        } catch (error) {
            window.maiaUi.setStatus(settingsStatus, error.message || 'Unable to save profile settings.', { error: true });
        }
    });

    root.querySelector('[data-profile-settings-cancel]')?.addEventListener('click', () => dialog.close());
    root.querySelector('[data-profiles-refresh]')?.addEventListener('click', () => { void loadProfiles(); });

    const panelContent = root.closest('.panel-content');
    const panelId = panelContent?.id;
    if (panelId) {
        document.addEventListener('maia:panel-open', (event) => {
            if (event.detail?.id === panelId) void loadProfiles();
        });
    } else {
        void loadProfiles();
    }
})();
