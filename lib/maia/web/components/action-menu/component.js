/* Reusable, viewport-bounded action menu for MAIA web components. */
(() => {
    'use strict';

    const instances = new Set();
    let activeInstance = null;
    let nextMenuId = 0;
    const margin = 8;
    const gap = 6;

    function removeFloatingStyles(menu) {
        for (const property of ['top', 'left', 'right', 'bottom', 'max-width', 'max-height']) {
            menu.style.removeProperty(property);
        }
    }

    function close(instance, restoreFocus = false) {
        if (!instance || instance.menu.hidden) return;
        instance.menu.hidden = true;
        instance.menu.classList.remove('maia-action-menu-popup-floating');
        if (instance.floatingMenuClass) instance.menu.classList.remove(instance.floatingMenuClass);
        removeFloatingStyles(instance.menu);
        instance.wrapper.appendChild(instance.menu);
        instance.trigger.setAttribute('aria-expanded', 'false');
        if (activeInstance === instance) activeInstance = null;
        if (restoreFocus) instance.trigger.focus();
    }

    function closeAll(except = null) {
        for (const instance of instances) {
            if (instance !== except) close(instance, false);
        }
    }

    function position(instance) {
        const { menu, trigger } = instance;
        const viewportWidth = document.documentElement.clientWidth || window.innerWidth;
        const viewportHeight = document.documentElement.clientHeight || window.innerHeight;
        const anchor = trigger.getBoundingClientRect();
        const maxWidth = Math.max(1, viewportWidth - 2 * margin);
        const spaceAbove = Math.max(1, anchor.top - margin - gap);
        const spaceBelow = Math.max(1, viewportHeight - anchor.bottom - margin - gap);

        menu.style.top = '0px';
        menu.style.left = '0px';
        menu.style.maxWidth = `${maxWidth}px`;
        menu.style.maxHeight = `${Math.max(spaceAbove, spaceBelow)}px`;

        const desiredHeight = menu.scrollHeight;
        const placeAbove = desiredHeight <= spaceAbove ||
            (desiredHeight > spaceBelow && spaceAbove > spaceBelow);
        const availableHeight = placeAbove ? spaceAbove : spaceBelow;
        menu.style.maxHeight = `${availableHeight}px`;

        const rect = menu.getBoundingClientRect();
        const desiredTop = placeAbove ? anchor.top - gap - rect.height : anchor.bottom + gap;
        const top = Math.max(margin, Math.min(desiredTop, viewportHeight - margin - rect.height));
        const width = Math.min(rect.width, maxWidth);
        const left = Math.max(margin, Math.min(anchor.right - width, viewportWidth - margin - width));
        menu.style.top = `${top}px`;
        menu.style.left = `${left}px`;
    }

    function currentItems(instance) {
        return typeof instance.items === 'function' ? instance.items() : instance.items;
    }

    function renderItems(instance) {
        const { menu, itemClassName, onError } = instance;
        menu.replaceChildren();
        for (const descriptor of currentItems(instance) || []) {
            if (descriptor.type === 'separator') {
                const separator = document.createElement('div');
                separator.className = 'maia-action-menu-separator';
                separator.setAttribute('role', 'separator');
                menu.appendChild(separator);
                continue;
            }

            const isLink = descriptor.type === 'link' && typeof descriptor.href === 'string';
            const item = document.createElement(isLink ? 'a' : 'button');
            if (!isLink) item.type = 'button';
            item.className = 'maia-action-menu-item';
            if (itemClassName) item.classList.add(itemClassName);
            if (descriptor.danger) item.classList.add('is-danger');
            if (isLink) item.href = descriptor.href;

            const role = descriptor.type === 'radio'
                ? 'menuitemradio'
                : (descriptor.type === 'checkbox' ? 'menuitemcheckbox' : 'menuitem');
            item.setAttribute('role', role);
            if (descriptor.type === 'radio' || descriptor.type === 'checkbox') {
                const checked = typeof descriptor.checked === 'function'
                    ? descriptor.checked()
                    : Boolean(descriptor.checked);
                item.setAttribute('aria-checked', String(checked));
            }
            const disabled = typeof descriptor.disabled === 'function'
                ? descriptor.disabled()
                : Boolean(descriptor.disabled);
            if (disabled) {
                item.setAttribute('aria-disabled', 'true');
                if (!isLink) item.disabled = true;
            }
            if (descriptor.ariaLabel) item.setAttribute('aria-label', descriptor.ariaLabel);
            if (descriptor.title) item.title = descriptor.title;

            if (descriptor.icon) {
                const icon = document.createElement('span');
                icon.className = 'maia-action-menu-item-icon';
                icon.setAttribute('aria-hidden', 'true');
                icon.textContent = descriptor.icon;
                item.appendChild(icon);
            }
            const label = document.createElement('span');
            label.className = 'maia-action-menu-item-label';
            label.textContent = descriptor.label || '';
            item.appendChild(label);

            item.addEventListener('click', (event) => {
                if (disabled) {
                    event.preventDefault();
                    return;
                }
                if (isLink) {
                    close(instance, false);
                    return;
                }
                event.preventDefault();
                event.stopPropagation();
                close(instance, true);
                if (typeof descriptor.run !== 'function') return;
                const run = () => descriptor.run(event);
                const operation = descriptor.busyText && window.maiaUi
                    ? window.maiaUi.runBusy(item, descriptor.busyText, run)
                    : Promise.resolve().then(run);
                void operation.catch((error) => {
                    if (typeof descriptor.onError === 'function') descriptor.onError(error);
                    else if (typeof onError === 'function') onError(error);
                    else console.error(error);
                });
            });
            menu.appendChild(item);
        }
    }

    function create(options = {}) {
        const wrapper = document.createElement('div');
        wrapper.className = 'maia-action-menu';
        if (options.wrapperClassName) wrapper.classList.add(options.wrapperClassName);

        const trigger = document.createElement('button');
        trigger.type = 'button';
        trigger.className = 'maia-action-menu-trigger';
        if (options.triggerClassName) trigger.classList.add(options.triggerClassName);
        trigger.setAttribute('aria-haspopup', 'menu');
        trigger.setAttribute('aria-expanded', 'false');
        trigger.setAttribute('aria-label', options.ariaLabel || options.triggerText || 'Open actions');
        if (options.title) trigger.title = options.title;
        if (options.triggerIcon) {
            const icon = document.createElement('span');
            icon.className = 'maia-action-menu-trigger-icon';
            icon.setAttribute('aria-hidden', 'true');
            icon.textContent = options.triggerIcon;
            trigger.appendChild(icon);
        }
        if (options.triggerText) {
            const text = document.createElement('span');
            text.className = 'maia-action-menu-trigger-text';
            text.textContent = options.triggerText;
            trigger.appendChild(text);
        }

        const menu = document.createElement('div');
        menu.id = options.menuId || `maia-action-menu-${++nextMenuId}`;
        menu.className = 'maia-action-menu-popup';
        if (options.menuClassName) menu.classList.add(options.menuClassName);
        menu.setAttribute('role', 'menu');
        menu.setAttribute('aria-label', options.menuLabel || options.ariaLabel || 'Actions');
        menu.hidden = true;
        trigger.setAttribute('aria-controls', menu.id);

        const instance = {
            wrapper,
            trigger,
            menu,
            items: options.items || [],
            itemClassName: options.itemClassName || '',
            floatingMenuClass: options.floatingMenuClass || '',
            onError: options.onError
        };
        instances.add(instance);

        trigger.addEventListener('click', (event) => {
            event.preventDefault();
            event.stopPropagation();
            if (activeInstance === instance && !menu.hidden) {
                close(instance, false);
                return;
            }
            closeAll(instance);
            renderItems(instance);
            menu.classList.add('maia-action-menu-popup-floating');
            if (instance.floatingMenuClass) menu.classList.add(instance.floatingMenuClass);
            document.body.appendChild(menu);
            menu.hidden = false;
            trigger.setAttribute('aria-expanded', 'true');
            activeInstance = instance;
            position(instance);
            menu.querySelector('[role^="menuitem"]:not([aria-disabled="true"])')?.focus();
        });

        menu.addEventListener('keydown', (event) => {
            const items = Array.from(menu.querySelectorAll('[role^="menuitem"]:not([aria-disabled="true"])'));
            if (event.key === 'Escape') {
                event.preventDefault();
                close(instance, true);
                return;
            }
            if (!['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key) || items.length === 0) return;
            event.preventDefault();
            const index = items.indexOf(document.activeElement);
            const nextIndex = event.key === 'Home' ? 0
                : (event.key === 'End' ? items.length - 1
                    : (index + (event.key === 'ArrowUp' ? -1 : 1) + items.length) % items.length);
            items[nextIndex].focus();
        });

        wrapper.append(trigger, menu);
        return wrapper;
    }

    document.addEventListener('pointerdown', (event) => {
        if (!activeInstance) return;
        const target = event.target instanceof Node ? event.target : null;
        if (!target || activeInstance.wrapper.contains(target) || activeInstance.menu.contains(target)) return;
        close(activeInstance, false);
    });
    document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape' && activeInstance) close(activeInstance, true);
    });
    const reposition = () => { if (activeInstance) position(activeInstance); };
    window.addEventListener('resize', reposition);
    document.addEventListener('scroll', reposition, true);

    window.maiaActionMenu = Object.freeze({ create, closeAll: () => closeAll() });
})();
