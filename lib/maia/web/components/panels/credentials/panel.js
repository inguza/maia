/* Credentials panel behavior. */
(() => {
    'use strict';

    const byId = (id) => document.getElementById(id);
    const api = (...args) => window.maiaApi.request(...args);
    let loaded = false;

    function setStatus(message, isError = false) {
        const node = byId('credentials-status');
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

    async function loadCredentials() {
        setStatus('Loading credentials…');
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
                        await api('/api/auth/context', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({ action: 'delete', identifier: credential.identifier })
                        });
                        loaded = false;
                        await loadCredentials();
                    } catch (error) { setStatus(error.message, true); }
                });
                item.append(value, remove);
                list.appendChild(item);
            }
            setStatus(result.credentials?.length ? '' : 'No credentials configured.');
            loaded = true;
        } catch (error) { setStatus(error.message, true); }
    }

    document.addEventListener('maia:panel-open', (event) => {
        if (event.detail?.id === 'credentials' && !loaded) loadCredentials();
    });

    byId('credential-create')?.addEventListener('click', async () => {
        const button = byId('credential-create');
        const name = byId('credential-name').value.trim();
        if (name && !/^[A-Za-z0-9_-]+$/.test(name)) {
            setStatus('Use only letters, digits, underscore, and hyphen.', true);
            return;
        }
        button.disabled = true;
        setStatus('Creating credential…');
        try {
            const result = await api('/api/auth/context', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ action: 'create', name })
            });
            loaded = false;
            await loadCredentials();
            const status = byId('credentials-status');
            status.replaceChildren();
            const message = document.createElement('span');
            message.textContent = 'Credential created. ';
            status.appendChild(message);
            for (const [href, text] of [[result.url, 'Open authentication URL'], [result.qrUrl, ' QR code']]) {
                if (!href) continue;
                const link = document.createElement('a');
                link.href = href;
                link.textContent = text;
                link.target = '_blank';
                link.rel = 'noopener noreferrer';
                status.appendChild(link);
            }
            byId('credential-name').value = '';
        } catch (error) { setStatus(error.message, true); }
        finally { button.disabled = false; }
    });
})();
