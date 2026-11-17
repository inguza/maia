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

    const actionTypes = ['action-cancel', 'action-normal', 'action-check', 'action-warning'];

    function setActionType(button, type) {
        if (!button || !actionTypes.includes(type)) return;
        button.classList.remove(...actionTypes);
        button.classList.add(type);
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

    function confirmAction({ title, message, actionLabel = 'OK', actionType = 'action-normal' }) {
        if (typeof HTMLDialogElement === 'undefined' || typeof HTMLDialogElement.prototype.showModal !== 'function') {
            return Promise.resolve(window.confirm(`${title}\n\n${message}`));
        }

        const dialog = document.createElement('dialog');
        dialog.className = 'maia-confirm-dialog';
        const form = document.createElement('form');
        form.method = 'dialog';
        const heading = document.createElement('h2');
        heading.textContent = title;
        const content = document.createElement('p');
        content.textContent = message;
        const actions = document.createElement('div');
        actions.className = 'maia-confirm-dialog-actions';
        const cancel = document.createElement('button');
        cancel.type = 'submit';
        cancel.value = 'cancel';
        cancel.textContent = 'Cancel';
        cancel.className = 'action-cancel';
        const confirm = document.createElement('button');
        confirm.type = 'submit';
        confirm.value = 'confirm';
        confirm.textContent = actionLabel;
        setActionType(confirm, actionType);
        actions.append(cancel, confirm);
        form.append(heading, content, actions);
        dialog.appendChild(form);

        return new Promise((resolve) => {
            dialog.addEventListener('close', () => {
                const accepted = dialog.returnValue === 'confirm';
                dialog.remove();
                resolve(accepted);
            }, { once: true });
            document.body.appendChild(dialog);
            dialog.showModal();
            cancel.focus();
        });
    }

    function inputAction({ title, label, value = '', actionLabel = title, actionType = 'action-normal' }) {
        if (typeof HTMLDialogElement === 'undefined' || typeof HTMLDialogElement.prototype.showModal !== 'function') {
            const answer = window.prompt(`${title}\n${label}:`, value);
            return Promise.resolve(answer);
        }

        const dialog = document.createElement('dialog');
        dialog.className = 'maia-input-dialog';
        const form = document.createElement('form');
        form.method = 'dialog';
        const heading = document.createElement('h2');
        heading.textContent = title;
        const fieldLabel = document.createElement('label');
        fieldLabel.className = 'maia-input-dialog-label';
        fieldLabel.textContent = label;
        const input = document.createElement('input');
        input.type = 'text';
        input.value = value;
        fieldLabel.appendChild(input);
        const actions = document.createElement('div');
        actions.className = 'maia-confirm-dialog-actions';
        const cancel = document.createElement('button');
        cancel.type = 'submit';
        cancel.value = 'cancel';
        cancel.textContent = 'Cancel';
        setActionType(cancel, 'action-cancel');
        const confirm = document.createElement('button');
        confirm.type = 'submit';
        confirm.value = 'confirm';
        confirm.textContent = actionLabel;
        setActionType(confirm, actionType);
        actions.append(cancel, confirm);
        form.append(heading, fieldLabel, actions);
        dialog.appendChild(form);

        return new Promise((resolve) => {
            dialog.addEventListener('close', () => {
                const result = dialog.returnValue === 'confirm' ? input.value : null;
                dialog.remove();
                resolve(result);
            }, { once: true });
            document.body.appendChild(dialog);
            dialog.showModal();
            input.focus();
            input.select();
        });
    }

    window.maiaUi = Object.freeze({ setStatus, setLoadingStatus, runBusy, bindBusyClick, setActionType, confirmAction, inputAction });
})();
