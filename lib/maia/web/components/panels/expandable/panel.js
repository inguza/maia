/* Shared disclosure behavior for expandable panels. */
(() => {
    'use strict';

    document.querySelectorAll('[data-expandable-panel]').forEach((panel) => {
        const toggle = panel.querySelector('.panel-toggle');
        const content = panel.querySelector('.panel-content');
        if (!toggle || !content) return;

        toggle.addEventListener('click', () => {
            const expanded = content.hidden;
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
        });
    });
})();
