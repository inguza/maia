/* Manage tasks visible to this session. */
(() => {
    'use strict';

    const root = document.querySelector('.tasks-panel');
    if (!root || !window.maiaApi || !window.maiaUi) return;
    const list = root.querySelector('[data-tasks-role="list"]');
    const statusNode = root.querySelector('[data-tasks-role="status"]');
    const form = root.querySelector('[data-tasks-form]');
    const createScope = root.querySelector('[data-tasks-role="create-scope"]');
    const createDescription = form.querySelector('textarea');
    const createToggle = root.querySelector('[data-tasks-action="toggle-create"]');
    const defaultStatuses = ['new', 'progress', 'done', 'cancelled'];
    let tasks = [];
    let loaded = false;

    function setStatus(message, error = false) {
        window.maiaUi.setStatus(statusNode, message, { error });
    }
    function setLoading(message) { window.maiaUi.setLoadingStatus(statusNode, message); }
    function linesText(lines) { return Array.isArray(lines) ? lines.join('\n') : String(lines || ''); }
    function requestAction(body) {
        return window.maiaApi.request('/api/task', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body)
        });
    }
    async function action(body, message) {
        const result = await requestAction(body);
        await loadTasks();
        setStatus(message || result.message || 'Task updated.');
    }
    function makeButton(label, title, handler, className = '') {
        const button = document.createElement('button');
        button.type = 'button';
        button.textContent = label;
        button.title = title;
        button.setAttribute('aria-label', title);
        if (className) button.className = className;
        window.maiaUi.bindBusyClick(button, handler, {
            busyText: `${label}...`,
            onError: (error) => setStatus(error.message || 'Task operation failed.', true)
        });
        return button;
    }

    function appendProgress(content, task) {
        const items = Array.isArray(task.progress) ? task.progress.filter((entry) => String(entry).trim() !== '') : [];
        const details = document.createElement('details');
        details.className = 'task-progress';
        const summary = document.createElement('summary');
        summary.className = 'task-progress-summary';
        summary.append(document.createTextNode(`Progress (${items.length}) `));
        const add = document.createElement('button');
        add.type = 'button';
        add.className = 'task-progress-add';
        add.textContent = '+';
        add.title = `Add a progress report to ${task.id}`;
        add.setAttribute('aria-label', `Add a progress report to ${task.id}`);
        summary.appendChild(add);

        const entries = document.createElement('ul');
        entries.className = 'task-progress-list';
        for (const entry of items) {
            const item = document.createElement('li');
            item.textContent = entry;
            entries.appendChild(item);
        }

        const reportForm = document.createElement('form');
        reportForm.className = 'task-report';
        reportForm.hidden = true;
        const report = document.createElement('textarea');
        report.rows = 2;
        report.placeholder = 'Add a progress report';
        report.setAttribute('aria-label', `Progress report for ${task.id}`);
        const submit = document.createElement('button');
        submit.type = 'submit';
        submit.textContent = '\u279C';
        submit.title = `Report progress for ${task.id}`;
        submit.setAttribute('aria-label', `Report progress for ${task.id}`);
        reportForm.append(report, submit);

        add.addEventListener('click', (event) => {
            event.preventDefault();
            event.stopPropagation();
            reportForm.hidden = !reportForm.hidden;
            if (!reportForm.hidden) report.focus();
        });
        reportForm.addEventListener('submit', (event) => {
            event.preventDefault();
            void window.maiaUi.runBusy(submit, 'Reporting progress...', async () => {
                const value = report.value.replace(/\s*[\r\n]+\s*/g, ' ').trim();
                if (!value) throw new Error('Enter a progress report.');
                await action({ action: 'report', id: task.id, version: task.version, progress: value }, `Reported progress for ${task.id}.`);
            }).catch((error) => setStatus(error.message || 'Unable to report progress.', true));
        });

        details.append(summary, reportForm, entries);
        content.appendChild(details);
    }

    function renderTask(task, expanded = false) {
        const card = document.createElement('article');
        card.className = 'task-card';
        card.dataset.taskId = task.id;
        card.dataset.expanded = String(expanded);

        const summary = document.createElement('button');
        summary.type = 'button';
        summary.className = 'task-card-summary';
        summary.setAttribute('aria-expanded', String(expanded));
        const id = document.createElement('strong');
        id.textContent = task.id;
        const scope = document.createElement('span');
        scope.className = 'task-scope';
        scope.textContent = task.scope;
        const version = document.createElement('span');
        version.className = 'task-version';
        version.textContent = `v${task.version}`;
        summary.append(id, scope, version);
        if (task.loaded) {
            const marker = document.createElement('span');
            marker.className = 'task-loaded-label';
            marker.textContent = 'Remembered';
            summary.appendChild(marker);
        }

        const controls = document.createElement('div');
        controls.className = 'task-card-controls';
        const statusSelect = document.createElement('select');
        statusSelect.className = 'task-status-select';
        statusSelect.setAttribute('aria-label', `Status for ${task.id}`);
        const originalStatus = task.status || '';
        const addOption = (value, label = value) => {
            const option = document.createElement('option');
            option.value = value;
            option.textContent = label;
            statusSelect.appendChild(option);
        };
        if (!originalStatus) addOption('', 'No status');
        for (const value of defaultStatuses) addOption(value);
        if (originalStatus && !defaultStatuses.includes(originalStatus)) addOption(originalStatus, originalStatus);
        addOption('__custom__', 'Custom…');
        statusSelect.value = originalStatus;

        const statusControl = document.createElement('div');
        statusControl.className = 'task-status-control';
        const statusInput = document.createElement('input');
        statusInput.type = 'text';
        statusInput.className = 'task-status-input';
        statusInput.setAttribute('aria-label', `Status for ${task.id}`);
        statusInput.placeholder = 'Status';
        statusInput.value = originalStatus;
        const statusSuggestions = document.createElement('div');
        statusSuggestions.className = 'task-status-suggestions';
        statusSuggestions.setAttribute('role', 'listbox');
        statusSuggestions.hidden = true;
        for (const value of defaultStatuses) {
            const option = document.createElement('button');
            option.type = 'button';
            option.className = 'task-status-option';
            option.textContent = value;
            option.setAttribute('role', 'option');
            option.addEventListener('mousedown', (event) => event.preventDefault());
            option.addEventListener('click', () => {
                statusInput.value = value;
                statusSuggestions.hidden = true;
                updateSaveVisibility();
                statusInput.focus();
            });
            statusSuggestions.appendChild(option);
        }
        statusControl.append(statusInput, statusSuggestions);

        const save = document.createElement('button');
        save.type = 'button';
        save.className = 'task-icon-button task-save';
        save.textContent = '\u2713';
        save.title = `Save changes to ${task.id}`;
        save.setAttribute('aria-label', `Save changes to ${task.id}`);
        save.hidden = true;

        const loadedButton = makeButton(
            task.loaded ? '\u2212' : '+',
            `${task.loaded ? 'Forget' : 'Remember'} task ${task.id} in this session`,
            () => action(
                { action: 'loaded', id: task.id, loaded: !task.loaded },
                `${task.loaded ? 'Forgot' : 'Remembered'} ${task.id} in this session.`
            ),
            'task-icon-button task-loaded-action'
        );
        const deleteButton = makeButton('\u00D7', `Delete task ${task.id}`, async () => {
            if (!await window.maiaUi.confirmAction({
                title: 'Delete task',
                message: `Delete ${task.id}? This cannot be undone.`,
                actionLabel: 'Delete',
                actionType: 'action-check'
            })) return;
            return action({ action: 'delete', id: task.id }, `Deleted ${task.id}.`);
        }, 'task-icon-button task-delete');
        controls.append(statusControl, save, loadedButton, deleteButton);

        const content = document.createElement('div');
        content.className = 'task-card-content';
        content.id = `task-content-${task.id}`;
        content.hidden = !expanded;
        summary.setAttribute('aria-controls', content.id);
        summary.addEventListener('click', () => {
            const opening = card.dataset.expanded !== 'true';
            card.dataset.expanded = String(opening);
            summary.setAttribute('aria-expanded', String(opening));
            content.hidden = !opening;
        });
        const description = document.createElement('textarea');
        description.className = 'task-description-editor';
        description.rows = Math.max(2, Math.min(6, linesText(task.description).split('\n').length));
        description.value = linesText(task.description);
        description.setAttribute('aria-label', `Description for ${task.id}`);
        description.placeholder = 'Task description';

        function selectedStatus() {
            return statusInput.value.trim();
        }
        function updateSaveVisibility() {
            const statusValue = selectedStatus();
            save.hidden = statusValue === originalStatus && description.value === linesText(task.description);
        }
        statusInput.addEventListener('focus', () => { statusSuggestions.hidden = false; });
        statusInput.addEventListener('input', () => {
            statusSuggestions.hidden = false;
            updateSaveVisibility();
        });
        statusInput.addEventListener('blur', () => {
            window.setTimeout(() => { statusSuggestions.hidden = true; }, 120);
        });
        description.addEventListener('input', updateSaveVisibility);

        save.addEventListener('click', () => {
            void window.maiaUi.runBusy(save, 'Saving task...', async () => {
                const statusValue = selectedStatus();
                const descriptionValue = description.value;
                if (!statusValue.trim()) throw new Error('Enter a task status.');
                if (!descriptionValue.trim()) throw new Error('Task description is required.');
                const operations = [];
                if (statusValue !== originalStatus) operations.push({ action: 'status', status: statusValue });
                if (descriptionValue !== linesText(task.description)) {
                    operations.push({ action: 'update', description: descriptionValue.split(/\r\n|\n|\r/) });
                }
                let versionNumber = Number(task.version);
                let versionValue = task.version;
                for (const operation of operations) {
                    await requestAction({ ...operation, id: task.id, version: versionValue });
                    if (Number.isFinite(versionNumber)) versionValue = String(++versionNumber);
                }
                await loadTasks();
                setStatus(`Updated ${task.id}.`);
            }).catch((error) => setStatus(error.message || 'Unable to save task.', true));
        });

        content.append(description);
        appendProgress(content, task);
        card.append(summary, controls, content);
        return card;
    }

    function renderTasks() {
        const expandedIds = new Set(Array.from(list.querySelectorAll('.task-card[data-expanded="true"]'), (card) => card.dataset.taskId));
        list.replaceChildren();
        if (tasks.length === 0) {
            const empty = document.createElement('p');
            empty.className = 'task-empty';
            empty.textContent = 'No tasks are available to this session.';
            list.appendChild(empty);
            return;
        }
        for (const task of tasks) list.appendChild(renderTask(task, expandedIds.has(task.id)));
    }

    async function loadTasks() {
        setLoading('Loading tasks...');
        try {
            const result = await window.maiaApi.request('/api/task');
            tasks = Array.isArray(result.tasks) ? result.tasks : [];
            renderTasks();
            loaded = true;
            setStatus(tasks.length ? '' : 'No tasks are available to this session.');
        } catch (error) {
            setStatus(error.message || 'Unable to load tasks.', true);
        }
    }

    form.addEventListener('submit', (event) => {
        event.preventDefault();
        const description = createDescription.value;
        if (!description.trim()) {
            setStatus('Enter a task description.', true);
            createDescription.focus();
            return;
        }
        const submit = form.querySelector('button[type="submit"]');
        void window.maiaUi.runBusy(submit, 'Creating task...', async () => {
            await action({ action: 'create', scope: createScope.value, description: description.split(/\r\n|\n|\r/) }, 'Created task.');
            createDescription.value = '';
            form.hidden = true;
            createToggle.setAttribute('aria-expanded', 'false');
            createToggle.textContent = '+';
        }).catch((error) => setStatus(error.message || 'Unable to create task.', true));
    });
    createToggle.addEventListener('click', () => {
        const opening = form.hidden;
        form.hidden = !opening;
        createToggle.setAttribute('aria-expanded', String(opening));
        createToggle.setAttribute('aria-label', opening ? 'Close task creation' : 'Create task');
        createToggle.title = opening ? 'Close task creation' : 'Create task';
        createToggle.textContent = opening ? '\u00D7' : '+';
        if (opening) createDescription.focus();
    });
    window.maiaUi.bindBusyClick(root.querySelector('[data-tasks-action="refresh"]'), loadTasks, {
        busyText: 'Refreshing tasks...',
        onError: (error) => setStatus(error.message || 'Unable to refresh tasks.', true)
    });
    function setTaskExpanded(card, expanded) {
        card.dataset.expanded = String(expanded);
        const toggle = card.querySelector('.task-card-summary');
        const content = card.querySelector('.task-card-content');
        if (toggle) toggle.setAttribute('aria-expanded', String(expanded));
        if (content) content.hidden = !expanded;
    }
    root.querySelector('[data-tasks-action="expand-all"]').addEventListener('click', () => {
        list.querySelectorAll('.task-card').forEach((card) => setTaskExpanded(card, true));
    });
    root.querySelector('[data-tasks-action="collapse-all"]').addEventListener('click', () => {
        list.querySelectorAll('.task-card').forEach((card) => setTaskExpanded(card, false));
    });
    document.addEventListener('maia:panel-open', (event) => {
        if (event.detail?.id === 'tasks' && !loaded) void loadTasks();
    });
    void loadTasks();
})();
