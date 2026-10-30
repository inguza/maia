/* Shared browser UI helpers used by web components. */
(() => {
    'use strict';

    function setStatus(target, message, { error = false } = {}) {
        const node = typeof target === 'string' ? document.getElementById(target) : target;
        if (!node) return;
        node.replaceChildren();
        node.textContent = message;
        node.classList.toggle('error', error);
    }

    function setLoadingStatus(target, message) {
        const node = typeof target === 'string' ? document.getElementById(target) : target;
        if (!node) return;
        const spinner = document.createElement('span');
        spinner.className = 'spinner';
        spinner.setAttribute('aria-hidden', 'true');
        const label = document.createElement('span');
        label.textContent = message;
        node.replaceChildren(spinner, label);
        node.classList.remove('error');
    }

    async function runBusy(button, busyText, callback) {
        if (!button || button.disabled) return;
        const originalNodes = Array.from(button.childNodes, (node) => node.cloneNode(true));
        button.disabled = true;
        button.setAttribute('aria-busy', 'true');
        button.replaceChildren();
        const spinner = document.createElement('span');
        spinner.className = 'spinner';
        spinner.setAttribute('aria-hidden', 'true');
        const label = document.createElement('span');
        label.className = 'visually-hidden';
        label.textContent = busyText || 'Working\u2026';
        button.append(spinner, label);
        try {
            return await callback();
        } finally {
            if (button.isConnected) {
                button.replaceChildren(...originalNodes);
                button.disabled = false;
                button.removeAttribute('aria-busy');
            }
        }
    }

    function bindBusyClick(button, callback, { busyText = 'Working\u2026', onError } = {}) {
        if (!button) return;
        button.addEventListener('click', (event) => {
            event.preventDefault();
            void runBusy(button, busyText, () => callback(event)).catch((error) => {
                if (typeof onError === 'function') onError(error);
                else console.error(error);
            });
        });
    }

    window.maiaUi = Object.freeze({ setStatus, setLoadingStatus, runBusy, bindBusyClick });
})();
