/* Shared disclosure behavior for expandable panels. */
(() => {
    'use strict';

    const initializeExpandablePanels = () => {
        document.querySelectorAll('[data-expandable-panel]').forEach((panel) => {
        const toggle = panel.querySelector('.panel-toggle');
        const content = panel.querySelector('.panel-content');
        if (!toggle || !content) return;

        const heading = content.querySelector('.panel-content-heading');
        const titleButton = content.querySelector('.panel-content-title');
        const headingActions = content.querySelector('.panel-content-heading-actions');
        const body = content.querySelector('.panel-content-body');
        const panelLabel = titleButton?.firstElementChild?.textContent.trim() || '';

        // Every expandable panel has one shared title, supplied by its panel
        // label. Promote matching content-header actions (for example Refresh)
        // into that shared row and remove duplicate inner titles.
        if (headingActions && body && panelLabel) {
            const originalRow = body.querySelector(
                ':scope > h2, :scope > header:first-child, :scope > .approvals-header, :scope > section:first-child > header:first-child, :scope > .path-browser > .path-browser-heading'
            );
            if (originalRow) {
                const originalTitle = originalRow.matches('h2') ? originalRow : originalRow.querySelector('h2');
                if (originalTitle && originalTitle.textContent.trim() === panelLabel) {
                    if (originalRow !== originalTitle) {
                        for (const child of [...originalRow.childNodes]) {
                            if (child === originalTitle) continue;
                            if (child.nodeType === Node.TEXT_NODE && child.textContent.trim() === '') continue;
                            headingActions.appendChild(child);
                        }
                    }
                    originalRow.remove();
                }
            }
        }

        const setExpanded = (expanded) => {
            panel.classList.toggle('expanded', expanded);
            content.hidden = !expanded;
            toggle.setAttribute('aria-expanded', String(expanded));
            const arrow = toggle.querySelector('[aria-hidden="true"]');
            if (arrow) arrow.textContent = expanded ? '\u25BE' : '\u25B8';
            if (expanded) {
                document.dispatchEvent(new CustomEvent('maia:panel-open', {
                    detail: { id: content.id }
                }));
            }
        };

        toggle.addEventListener('click', (event) => {
            event.preventDefault();
            setExpanded(toggle.getAttribute('aria-expanded') !== 'true');
        });

        titleButton?.addEventListener('click', (event) => {
            event.preventDefault();
            setExpanded(false);
        });

        // The whole grey row is a collapse target, except its action controls.
        heading?.addEventListener('click', (event) => {
            if (event.target.closest('button, a, input, select, textarea')) return;
            setExpanded(false);
        });
        });
    };

    // This script is emitted before the wrapped component's script. Always
    // wait until parsing is complete so component scripts can find and bind
    // their header controls before those controls are moved into the shared
    // expandable heading. At the end of the document the readyState may
    // already be "interactive" even though later component scripts have not
    // run yet, so an immediate initialization is not safe here.
    document.addEventListener('DOMContentLoaded', initializeExpandablePanels, { once: true });
})();
