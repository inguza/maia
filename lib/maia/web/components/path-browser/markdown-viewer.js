/**
 * MAIA markdown viewer
 *
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */

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

    function render(source) {
        if (!window.marked || typeof window.marked.lexer !== 'function' ||
            typeof window.marked.parser !== 'function' || !window.DOMPurify) {
            throw new Error('The Markdown viewer libraries did not load.');
        }

        const renderer = new window.marked.Renderer();
        renderer.html = (token) => {
            // Treat authored HTML as literal text. The sanitizer below is a
            // second boundary for parser-generated HTML.
            return escapeHtml(token.text || '');
        };
        const options = {
            gfm: true,
            breaks: false,
            renderer
        };
        const tokens = window.marked.lexer(source, options);
        const links = tokens.links || Object.create(null);
        const fragment = document.createDocumentFragment();
        let cursor = 0;

        for (const token of tokens) {
            const raw = typeof token.raw === 'string' ? token.raw : '';
            let offset = raw === '' ? cursor : source.indexOf(raw, cursor);
            if (offset < 0) {
                offset = cursor;
            }
            const startLine = lineAt(source, offset);
            let lastOffset = offset + Math.max(0, raw.length - 1);
            while (lastOffset > offset && /[\r\n]/.test(source[lastOffset])) {
                lastOffset--;
            }
            const endLine = lineAt(source, lastOffset);
            cursor = offset + raw.length;

            if (token.type === 'space' || token.type === 'def') {
                continue;
            }

            const oneToken = [token];
            oneToken.links = links;
            const rendered = window.marked.parser(oneToken, options);
            if (!rendered || rendered.trim() === '') {
                continue;
            }

            const safeHtml = window.DOMPurify.sanitize(rendered, {
                USE_PROFILES: { html: true }
            });
            const block = document.createElement('div');
            const safeEndLine = Math.max(startLine, endLine);
            const lineLabel = startLine === safeEndLine
                ? String(startLine)
                : `${startLine}–${safeEndLine}`;
            block.className = 'workspace-markdown-block';
            block.dataset.lineStart = String(startLine);
            block.dataset.lineEnd = String(safeEndLine);
            block.tabIndex = 0;
            block.setAttribute('role', 'group');
            block.setAttribute('aria-label', `Markdown block from source lines ${lineLabel}`);

            const lineNumber = document.createElement('span');
            lineNumber.className = 'workspace-markdown-line-number';
            lineNumber.textContent = lineLabel;
            lineNumber.setAttribute('aria-hidden', 'true');

            const content = document.createElement('div');
            content.className = 'workspace-markdown-block-content';
            // safeHtml has been sanitized, and authored raw HTML was escaped
            // by the Marked renderer above.
            content.innerHTML = safeHtml;
            block.append(lineNumber, content);
            fragment.appendChild(block);
        }
        return fragment;
    }

    window.maiaRenderWorkspaceMarkdown = render;
})();
