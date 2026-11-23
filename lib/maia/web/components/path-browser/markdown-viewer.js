/* PathBrowser adapter: add source-line wrappers around shared safe Markdown blocks. */
(() => {
    'use strict';

    function render(source) {
        if (!window.maiaMarkdown || typeof window.maiaMarkdown.renderBlocks !== 'function') {
            throw new Error('The shared Markdown renderer did not load.');
        }

        const fragment = document.createDocumentFragment();
        for (const block of window.maiaMarkdown.renderBlocks(source)) {
            const startLine = block.startLine;
            const endLine = block.endLine;
            const lineLabel = startLine === endLine
                ? String(startLine)
                : `${startLine}–${endLine}`;
            const wrapper = document.createElement('div');
            wrapper.className = 'workspace-markdown-block';
            wrapper.dataset.lineStart = String(startLine);
            wrapper.dataset.lineEnd = String(endLine);
            wrapper.tabIndex = 0;
            wrapper.setAttribute('role', 'group');
            wrapper.setAttribute('aria-label', `Markdown block from source lines ${lineLabel}`);

            const lineNumber = document.createElement('span');
            lineNumber.className = 'workspace-markdown-line-number';
            lineNumber.textContent = lineLabel;
            lineNumber.setAttribute('aria-hidden', 'true');

            const content = document.createElement('div');
            content.className = 'workspace-markdown-block-content';
            content.innerHTML = block.html;
            wrapper.append(lineNumber, content);
            fragment.appendChild(wrapper);
        }
        return fragment;
    }

    window.maiaRenderWorkspaceMarkdown = render;
})();
