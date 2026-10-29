/* Shared browser API client. Page context is supplied by data-* attributes on <body>. */
(() => {
    'use strict';

    const basePath = String(window.MAIA_BASE_PATH || '').replace(/\/$/, '');
    const contextHeaders = [
        ['maiaHome', 'X-MAIA-Home'],
        ['maiaSession', 'X-MAIA-Session'],
        ['maiaWorkspace', 'X-MAIA-Workspace'],
        ['maiaProfile', 'X-MAIA-Profile']
    ];

    function url(path) {
        return `${basePath}${path.startsWith('/') ? path : `/${path}`}`;
    }

    async function request(path, options = {}) {
        const headers = new Headers(options.headers || {});
        for (const [attribute, header] of contextHeaders) {
            const value = document.body?.dataset?.[attribute];
            if (value) headers.set(header, value);
        }

        const response = await fetch(url(path), { ...options, headers });
        let result;
        try {
            result = await response.json();
        } catch (_) {
            throw new Error(`The server returned an invalid response (${response.status}).`);
        }
        if (!response.ok || result?.ok === false) {
            throw new Error(result?.error || `Request failed (${response.status}).`);
        }
        return result;
    }

    window.maiaApi = Object.freeze({ request, url });
})();
