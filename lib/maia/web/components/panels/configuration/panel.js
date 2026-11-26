/* Scope-aware configuration panel. */
(() => {
    'use strict';

    const byId = (id) => document.getElementById(id);
    const endpoint = '/api/config/context';
    const status = byId('config-status');
    const refreshButton = byId('config-refresh');
    const settingsList = byId('config-settings-list');
    const settingsEmpty = byId('config-settings-empty');
    const credentialsList = byId('config-credentials-list');
    const credentialsEmpty = byId('config-credentials-empty');
    const credentialForm = byId('config-credential-form');
    const credentialSave = byId('config-credential-save');
    const modelSpecificList = byId('config-model-specific-list');
    const modelSpecificEmpty = byId('config-model-specific-empty');
    const costsList = byId('config-costs-list');
    const costsEmpty = byId('config-costs-empty');
    const settingsTab = byId('config-settings-tab');
    const credentialsTab = byId('config-credentials-tab');
    const modelSpecificTab = byId('config-model-specific-tab');
    const costsTab = byId('config-costs-tab');
    const settingsPanel = byId('config-settings-panel');
    const credentialsPanel = byId('config-credentials-panel');
    const modelSpecificPanel = byId('config-model-specific-panel');
    const costsPanel = byId('config-costs-panel');
    const costForm = byId('config-cost-form');
    const costSave = byId('config-cost-save');
    const modelSpecificForm = byId('config-model-specific-form');
    const modelSpecificSave = byId('config-model-specific-save');
    const tabs = [
        { name: 'settings', button: settingsTab, panel: settingsPanel },
        { name: 'credentials', button: credentialsTab, panel: credentialsPanel },
        { name: 'model-specific', button: modelSpecificTab, panel: modelSpecificPanel },
        { name: 'costs', button: costsTab, panel: costsPanel }
    ];
    let settingsLoaded = false;
    let costsLoaded = false;
    let credentialsLoaded = false;
    let currentScope = 'session';
    let currentScopeLabel = 'this session';

    function setStatus(message, error = false) {
        window.maiaUi.setStatus(status, message, { error });
    }

    function setLoading(message) {
        window.maiaUi.setLoadingStatus(status, message);
    }

    function jsonOptions(body) {
        return {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body)
        };
    }

    function selectTab(name, focus = false) {
        for (const tab of tabs) {
            const active = tab.name === name;
            tab.button.setAttribute('aria-selected', String(active));
            tab.button.tabIndex = active ? 0 : -1;
            tab.panel.hidden = !active;
        }
        if (focus) tabs.find((tab) => tab.name === name)?.button.focus();
    }

    for (const [index, tab] of tabs.entries()) {
        tab.button.addEventListener('click', () => {
            selectTab(tab.name);
            if (tab.name === 'costs' && !costsLoaded) void loadCosts();
        });
        tab.button.addEventListener('keydown', (event) => {
            let next = null;
            if (event.key === 'ArrowRight' || event.key === 'ArrowDown') next = (index + 1) % tabs.length;
            if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') next = (index + tabs.length - 1) % tabs.length;
            if (event.key === 'Home') next = 0;
            if (event.key === 'End') next = tabs.length - 1;
            if (next !== null) {
                event.preventDefault();
                selectTab(tabs[next].name, true);
            }
        });
    }

    function makeIconButton(icon, label, handler) {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'config-icon-button';
        button.textContent = icon;
        button.title = label;
        button.setAttribute('aria-label', label);
        button.addEventListener('click', handler);
        return button;
    }

    function sourceName(scope) {
        const labels = {
            session: 'Session',
            profile: 'Profile',
            workspace: 'Workspace',
            home: 'Home',
            user: 'User',
            system: 'System',
            default: 'Default',
            env: 'Environment'
        };
        return labels[scope] || scope || 'Unknown';
    }

    function displayValue(value) {
        return value === '' ? '(empty)' : String(value);
    }

    function createSettingRow(list, setting, isLocal, isCredential = false, configType = 'general') {
        const item = document.createElement('tr');

        const key = document.createElement('td');
        key.className = 'config-key';
        key.textContent = setting.key;

        const value = document.createElement('td');
        value.className = 'config-value';
        value.textContent = displayValue(setting.value);
        if (setting.value === '') value.classList.add('empty');

        const sourceCell = document.createElement('td');
        const source = document.createElement('span');
        source.className = 'config-source';
        source.textContent = sourceName(setting.source);
        source.title = `Value from ${sourceName(setting.source)}`;
        sourceCell.appendChild(source);

        const actions = document.createElement('span');
        actions.className = 'config-actions';
        const edit = makeIconButton('\u270e', `Edit ${setting.key} for ${currentScopeLabel}`, () => {
            beginEdit(item, list, setting, isLocal, isCredential, configType);
        });
        actions.appendChild(edit);
        if (isLocal) {
            const remove = makeIconButton('\u00d7', `Delete ${setting.key} from ${currentScopeLabel}`, () => {
                if (isCredential) {
                    void performCredentialAction({ type: 'credentials', action: 'credential-delete', key: setting.key }, `Deleted ${setting.key}; the next available value is now in use.`);
                } else {
                    void performAction({ type: configType, action: 'delete', key: setting.key }, `Deleted ${setting.key}; the next available value is now in use.`);
                }
            });
            actions.appendChild(remove);
        }
        const actionCell = document.createElement('td');
        actionCell.appendChild(actions);
        item.append(key, value, sourceCell, actionCell);
        return item;
    }

    function beginEdit(item, list, setting, isLocal, isCredential = false, configType = 'general') {
        const valueCell = item.children[1];
        const actionsCell = item.children[3];
        const input = document.createElement('input');
        input.type = isCredential ? 'password' : 'text';
        input.value = isCredential ? '' : String(setting.value ?? '');
        if (isCredential) input.placeholder = 'Enter credential value';
        input.setAttribute('aria-label', `Value for ${setting.key}`);

        const actions = document.createElement('span');
        actions.className = 'config-actions';
        const save = makeIconButton('\u2713', `Save ${setting.key} for ${currentScopeLabel}`, () => {
            if (input.value === '') {
                setStatus(isCredential ? 'Enter a credential value to save.' : 'An empty value cannot be saved. Use Delete to remove a scope value.', true);
                input.focus();
                return;
            }
            if (isCredential) {
                void performCredentialAction({ type: 'credentials', action: 'credential-set', key: setting.key, value: input.value }, `Saved ${setting.key} for ${currentScopeLabel}.`, save);
            } else {
                void performAction({ type: configType, action: 'set', key: setting.key, value: input.value }, `Saved ${setting.key} for ${currentScopeLabel}.`, save);
            }
        });
        const cancel = makeIconButton('\u21a9', `Cancel editing ${setting.key}`, () => {
            item.replaceWith(createSettingRow(list, setting, isLocal, isCredential, configType));
        });
        actions.append(save, cancel);
        valueCell.replaceChildren(input);
        actionsCell.replaceChildren(actions);
        input.focus();
        input.select();
        input.addEventListener('keydown', (event) => {
            if (event.key === 'Enter') {
                event.preventDefault();
                save.click();
            } else if (event.key === 'Escape') {
                event.preventDefault();
                cancel.click();
            }
        });
    }

    function isModelSpecificSetting(setting) {
        return /^(file_handling_mode_|reasoning_effort_).+/.test(setting.key);
    }

    function renderSettingsList(list, emptyMessage, settings, configType = 'general') {
        list.replaceChildren();
        for (const setting of settings) {
            list.appendChild(createSettingRow(list, setting, setting.source === currentScope, false, configType));
        }
        emptyMessage.hidden = settings.length > 0;
    }

    function renderCredentials(result) {
        credentialsList.replaceChildren();
        const credentials = Array.isArray(result.credentials) ? result.credentials : [];
        for (const credential of credentials) {
            const setting = {
                key: credential.key,
                value: credential.configured ? '********************************' : '(not set)',
                source: credential.source || 'default'
            };
            credentialsList.appendChild(createSettingRow(credentialsList, setting, credential.local, true));
            continue;

            const row = document.createElement('tr');
            const keyCell = document.createElement('td');
            keyCell.className = 'config-key';
            keyCell.textContent = credential.key;
            const statusCell = document.createElement('td');
            statusCell.textContent = credential.source === 'environment' ? 'environment' : 'Set (value hidden)';
            const scopeCell = document.createElement('td');
            const source = document.createElement('span');
            source.className = 'config-source';
            source.textContent = sourceName(credential.source);
            scopeCell.appendChild(source);
            const actionCell = document.createElement('td');
            if (credential.local) {
                const remove = makeIconButton('×', `Delete ${credential.key} from ${currentScopeLabel}`, () => {
                    void performCredentialAction({ type: 'credentials', action: 'credential-delete', key: credential.key }, `Deleted ${credential.key} from ${currentScopeLabel}.`);
                });
                actionCell.appendChild(remove);
            }
            row.append(keyCell, statusCell, scopeCell, actionCell);
            credentialsList.appendChild(row);
        }
        credentialsEmpty.hidden = credentials.length > 0;
        credentialsLoaded = true;
    }

    function render(result) {
        currentScope = result.scope || 'session';
        currentScopeLabel = result.scopeLabel || `this ${currentScope}`;

        const local = Array.isArray(result.local) ? result.local : [];
        const groups = Array.isArray(result.otherScopes) ? result.otherScopes : [];
        const other = groups.flatMap((group) =>
            Array.isArray(group.values)
                ? group.values.map((setting) => ({ ...setting, source: group.scope }))
                : []
        );
        other.sort((a, b) => a.key.localeCompare(b.key));
        const current = local.map((setting) => ({ ...setting, source: currentScope }));
        const splitByTab = (matches) => [...current.filter(matches), ...other.filter(matches)];
        const settings = splitByTab((setting) => !isModelSpecificSetting(setting));
        const modelSpecific = splitByTab(isModelSpecificSetting);

        renderSettingsList(settingsList, settingsEmpty, settings);
        renderSettingsList(modelSpecificList, modelSpecificEmpty, modelSpecific);
        settingsLoaded = true;
    }

    function renderCosts(result) {
        currentScope = result.scope || currentScope;
        currentScopeLabel = result.scopeLabel || currentScopeLabel;
        const local = Array.isArray(result.local) ? result.local : [];
        const groups = Array.isArray(result.otherScopes) ? result.otherScopes : [];
        const other = groups.flatMap((group) =>
            Array.isArray(group.values)
                ? group.values.map((setting) => ({ ...setting, source: group.scope }))
                : []
        );
        other.sort((a, b) => a.key.localeCompare(b.key));
        const costs = [
            ...local.map((setting) => ({ ...setting, source: currentScope })),
            ...other
        ];
        renderSettingsList(costsList, costsEmpty, costs, 'cost');
        costsLoaded = true;
    }

    async function loadCosts() {
        try {
            const result = await window.maiaApi.request(`${endpoint}?type=cost`);
            renderCosts(result);
        } catch (error) {
            setStatus(error.message || 'Unable to load model costs.', true);
        }
    }

    async function loadConfig() {
        setLoading('Loading configuration…');
        try {
            const [result, costs, credentials] = await Promise.all([
                window.maiaApi.request(endpoint),
                window.maiaApi.request(`${endpoint}?type=cost`),
                window.maiaApi.request(`${endpoint}?type=credentials`)
            ]);
            render(result);
            renderCosts(costs);
            renderCredentials(credentials);
            setStatus('');
        } catch (error) {
            setStatus(error.message || 'Unable to load configuration.', true);
        }
    }

    async function performCredentialAction(body, successMessage, busyButton = null) {
        const operation = async () => {
            setLoading(body.action === 'credential-delete' ? 'Deleting credential…' : 'Saving credential…');
            try {
                const result = await window.maiaApi.request(endpoint, jsonOptions(body));
                renderCredentials(result);
                setStatus(successMessage);
            } catch (error) {
                setStatus(error.message || 'Unable to update credential.', true);
            }
        };
        if (busyButton) {
            await window.maiaUi.runBusy(busyButton, 'Saving…', operation);
        } else {
            await operation();
        }
    }

    async function performAction(body, successMessage, busyButton = null) {
        const operation = async () => {
            setLoading(body.action === 'delete' ? 'Deleting configuration value…' : 'Saving configuration value…');
            try {
                const result = await window.maiaApi.request(endpoint, jsonOptions(body));
                if (body.type === 'cost') {
                    const costs = await window.maiaApi.request(`${endpoint}?type=cost`);
                    renderCosts(costs);
                } else {
                    render(result);
                }
                setStatus(successMessage);
            } catch (error) {
                setStatus(error.message || 'Unable to update configuration.', true);
            }
        };
        if (busyButton) {
            await window.maiaUi.runBusy(busyButton, 'Saving…', operation);
        } else {
            await operation();
        }
    }

    credentialForm?.addEventListener('submit', (event) => {
        event.preventDefault();
        const key = byId('config-credential-key').value.trim();
        const value = byId('config-credential-value').value;
        if (!/^[a-z0-9_]+$/.test(key)) {
            setStatus('Credential names must use lowercase letters, numbers, and underscores.', true);
            return;
        }
        if (value === '') {
            setStatus('Enter a credential value.', true);
            return;
        }
        void window.maiaUi.runBusy(credentialSave, 'Adding credential…', async () => {
            setLoading('Saving credential…');
            try {
                const result = await window.maiaApi.request(endpoint, jsonOptions({
                    type: 'credentials', action: 'credential-set', key, value
                }));
                renderCredentials(result);
                credentialForm.reset();
                setStatus(`Saved ${key} for ${currentScopeLabel}.`);
            } catch (error) {
                setStatus(error.message || 'Unable to save credential.', true);
            }
        });
    });

    document.addEventListener('maia:panel-open', (event) => {
        if (event.detail?.id === 'configuration' && (!settingsLoaded || !costsLoaded || !credentialsLoaded)) void loadConfig();
    });

    window.maiaUi.bindBusyClick(refreshButton, async () => {
        settingsLoaded = false;
        costsLoaded = false;
        credentialsLoaded = false;
        await loadConfig();
    }, {
        busyText: 'Refreshing configuration...',
        onError: (error) => setStatus(error.message || 'Unable to refresh configuration.', true)
    });

    function commonPrefix(values) {
        if (values.length === 0) return '';
        let prefix = values[0];
        for (const value of values.slice(1)) {
            let length = 0;
            while (length < prefix.length && length < value.length && prefix[length] === value[length]) length++;
            prefix = prefix.slice(0, length);
        }
        return prefix;
    }

    function attachModelSettingCompletion(input, dropdown, getCandidates) {
        let candidates = [];

        function refresh() {
            const query = input.value;
            const lowerQuery = query.toLocaleLowerCase();
            candidates = [...new Set(getCandidates())]
                .filter((candidate) => candidate.toLocaleLowerCase().startsWith(lowerQuery));
            dropdown.replaceChildren();
            for (const candidate of candidates) {
                const option = document.createElement('button');
                option.type = 'button';
                option.textContent = candidate;
                option.setAttribute('role', 'option');
                option.addEventListener('mousedown', (event) => {
                    event.preventDefault();
                    input.value = candidate;
                    input.dispatchEvent(new Event('input', { bubbles: true }));
                    input.focus();
                });
                dropdown.appendChild(option);
            }
            dropdown.hidden = candidates.length === 0;
        }

        input.addEventListener('input', refresh);
        input.addEventListener('focus', refresh);
        input.addEventListener('blur', () => {
            window.setTimeout(() => { dropdown.hidden = true; }, 100);
        });
        input.addEventListener('keydown', (event) => {
            if (event.key === 'Escape') {
                dropdown.hidden = true;
                return;
            }
            if (event.key !== 'Tab' || candidates.length === 0) return;
            const completion = candidates.length === 1 ? candidates[0] : commonPrefix(candidates);
            if (completion && completion !== input.value) {
                event.preventDefault();
                input.value = completion;
                refresh();
            }
        });
    }

    const modelSettingKeyInput = byId('config-model-specific-key');
    const modelSettingValueInput = byId('config-model-specific-value');
    attachModelSettingCompletion(
        modelSettingKeyInput,
        byId('config-model-specific-key-suggestions'),
        () => ['file_handling_mode_', 'reasoning_effort_']
    );
    attachModelSettingCompletion(
        modelSettingValueInput,
        byId('config-model-specific-value-suggestions'),
        () => {
            const key = modelSettingKeyInput.value.toLocaleLowerCase();
            if (key.startsWith('reasoning_effort_')) {
                return ['none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max'];
            }
            if (key.startsWith('file_handling_mode_')) {
                return ['DEFAULT', 'FIRST', 'BEFORE', 'APPEND', 'AUTOTOOL'];
            }
            return [];
        }
    );

    modelSpecificForm?.addEventListener('submit', (event) => {
        event.preventDefault();
        const key = byId('config-model-specific-key').value.trim();
        const value = byId('config-model-specific-value').value.trim();
        if (!/^(file_handling_mode|reasoning_effort)_[A-Za-z0-9_]+$/.test(key)) {
            setStatus('Use a parameter name like file_handling_mode_model_name or reasoning_effort_model_name.', true);
            return;
        }
        if (value === '') {
            setStatus('Enter a value for the model-specific parameter.', true);
            return;
        }
        void window.maiaUi.runBusy(modelSpecificSave, 'Adding parameter…', async () => {
            setLoading('Saving model-specific parameter…');
            try {
                const result = await window.maiaApi.request(endpoint, jsonOptions({
                    action: 'add-model-setting', key, value
                }));
                render(result);
                modelSpecificForm.reset();
                setStatus(`Saved ${key} for ${currentScopeLabel}.`);
            } catch (error) {
                setStatus(error.message || 'Unable to save model-specific parameter.', true);
            }
        });
    });

    costForm?.addEventListener('submit', (event) => {
        event.preventDefault();
        const model = byId('config-cost-model').value.trim();
        const inputCost = byId('config-cost-input').value.trim();
        const outputCost = byId('config-cost-output').value.trim();
        if (!inputCost && !outputCost) {
            setStatus('Enter an input cost, an output cost, or both.', true);
            return;
        }
        void window.maiaUi.runBusy(costSave, 'Adding model cost…', async () => {
            setLoading('Saving model costs…');
            try {
                await window.maiaApi.request(endpoint, jsonOptions({
                    action: 'add-cost', model, inputCost, outputCost
                }));
                const result = await window.maiaApi.request(`${endpoint}?type=cost`);
                renderCosts(result);
                costForm.reset();
                setStatus(`Saved model costs for ${model}.`);
            } catch (error) {
                setStatus(error.message || 'Unable to save model costs.', true);
            }
        });
    });
})();
