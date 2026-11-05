/* Full-page view and controls for one session change. */
(() => {
    'use strict';

    const id = String(document.body.dataset.maiaChangeId || '');
    const status = document.getElementById('change-page-status');
    const meta = document.getElementById('change-page-meta');
    const controls = document.getElementById('change-page-controls');
    const detail = document.getElementById('change-page-detail');
    const states = ['pending', 'running', 'applied', 'skipped', 'finished', 'failed'];
    if (!id || !status || !meta || !controls || !detail || !window.maiaApi) return;

    const titleCase = (value) => value ? value[0].toUpperCase() + value.slice(1) : value;

    function setStatus(message, error = false) {
        status.textContent = message;
        status.classList.toggle('error', error);
    }

    function addButton(label, action, change) {
        const button = document.createElement('button');
        button.type = 'button';
        button.textContent = label;
        button.addEventListener('click', () => void runAction(action, change));
        controls.appendChild(button);
    }

    function renderControls(change) {
        controls.replaceChildren();
        const stateSelect = document.createElement('select');
        stateSelect.setAttribute('aria-label', 'Change state');
        for (const state of states) {
            const option = document.createElement('option');
            option.value = state;
            option.textContent = titleCase(state);
            option.selected = state === change.state;
            stateSelect.appendChild(option);
        }
        controls.appendChild(stateSelect);
        const setButton = document.createElement('button');
        setButton.type = 'button';
        setButton.textContent = 'Set state';
        setButton.addEventListener('click', () => void runAction(stateSelect.value, change));
        controls.appendChild(setButton);

        if (change.type === 'patch' && change.state === 'pending') {
            addButton('Apply', 'apply', change);
        } else if (change.type === 'patch' && change.state === 'applied') {
            addButton('Revert', 'revert', change);
        } else if ((change.type === 'shell' || change.type === 'action') && change.state === 'pending') {
            addButton('Do', 'do', change);
        }
    }

    async function loadChange() {
        setStatus('Loading change details...');
        try {
            const result = await window.maiaApi.request(`/api/change/show?id=${encodeURIComponent(id)}`);
            const change = result.change || {};
            meta.replaceChildren();
            const typeLabel = ` (${change.type || 'unknown'})`;
            if (change.filename) {
                if (typeof change.fileUrl === 'string' && change.fileUrl !== '') {
                    const fileLink = document.createElement('a');
                    fileLink.href = change.fileUrl;
                    fileLink.textContent = change.filename;
                    fileLink.title = `View ${change.filename}`;
                    meta.appendChild(fileLink);
                } else {
                    meta.appendChild(document.createTextNode(change.filename));
                }
            } else {
                meta.appendChild(document.createTextNode('No filename'));
            }
            meta.appendChild(document.createTextNode(typeLabel));
            detail.textContent = String(result.detail || '(No change details.)');
            renderControls(change);
            setStatus('');
        } catch (error) {
            setStatus(error.message || 'Unable to load change details.', true);
            detail.textContent = '';
            controls.replaceChildren();
        }
    }

    async function runAction(action, change) {
        if (action === 'do' && !window.confirm(`Run the proposed action for change ${id}?`)) return;
        for (const control of controls.querySelectorAll('button, select')) control.disabled = true;
        setStatus(`${titleCase(action)} change...`);
        try {
            const result = await window.maiaApi.request('/api/change/action', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ id: change.id || id, action })
            });
            await loadChange();
            if (result.message) setStatus(result.message);
        } catch (error) {
            setStatus(error.message || 'Unable to update change.', true);
        } finally {
            for (const control of controls.querySelectorAll('button, select')) control.disabled = false;
        }
    }

    void loadChange();
})();
