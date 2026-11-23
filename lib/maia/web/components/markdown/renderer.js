/* Shared safe Markdown rendering for MAIA web components. */
(() => {
    'use strict';

    function escapeHtml(value) {
        return String(value).replace(/[&<>"']/g, (character) => ({
            '&': '&amp;',
            '<': '&lt;',
            '>': '&gt;',
            '"': '&quot;',
            "'": '&#39;'
        })[character]);
    }

    function lineAt(source, offset) {
        return source.slice(0, Math.max(0, offset)).split(/\r\n|\n|\r/).length;
    }

    function renderBlocks(source) {
        source = String(source ?? '');
        if (!window.marked || typeof window.marked.lexer !== 'function' ||
            typeof window.marked.parser !== 'function' || !window.DOMPurify) {
            throw new Error('The Markdown rendering libraries did not load.');
        }

        const renderer = new window.marked.Renderer();
        renderer.html = (token) => escapeHtml(token.text || '');
        const options = { gfm: true, breaks: false, renderer };
        const tokens = window.marked.lexer(source, options);
        const links = tokens.links || Object.create(null);
        const blocks = [];
        let cursor = 0;

        for (const token of tokens) {
            const raw = typeof token.raw === 'string' ? token.raw : '';
            let offset = raw === '' ? cursor : source.indexOf(raw, cursor);
            if (offset < 0) offset = cursor;
            const startLine = lineAt(source, offset);
            let lastOffset = offset + Math.max(0, raw.length - 1);
            while (lastOffset > offset && /[\r\n]/.test(source[lastOffset])) lastOffset--;
            const endLine = Math.max(startLine, lineAt(source, lastOffset));
            cursor = offset + raw.length;

            if (token.type === 'space' || token.type === 'def') continue;
            const oneToken = [token];
            oneToken.links = links;
            const rendered = window.marked.parser(oneToken, options);
            if (!rendered || rendered.trim() === '') continue;
            const html = window.DOMPurify.sanitize(rendered, {
                USE_PROFILES: { html: true }
            });
            blocks.push({ html, startLine, endLine });
        }
        return blocks;
    }

    function render(source) {
        const fragment = document.createDocumentFragment();
        for (const block of renderBlocks(source)) {
            const template = document.createElement('template');
            template.innerHTML = block.html;
            fragment.appendChild(template.content);
        }
        return fragment;
    }

    window.maiaMarkdown = { render, renderBlocks };
})();
