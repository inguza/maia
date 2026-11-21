<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */
?>
<header class="panel-content-header">
    <h2>Config</h2>
    <button id="config-refresh" class="small-action" type="button" title="Refresh configuration" aria-label="Refresh configuration">&#x21BB;</button>
</header>
<p id="config-status" class="status" role="status" aria-live="polite"></p>
<div class="config-tabs" role="tablist" aria-label="Configuration sections">
    <button id="config-settings-tab" class="config-tab" type="button" role="tab" aria-selected="true" aria-controls="config-settings-panel" tabindex="0">Settings</button>
    <button id="config-credentials-tab" class="config-tab" type="button" role="tab" aria-selected="false" aria-controls="config-credentials-panel" tabindex="-1">Credentials</button>
    <button id="config-model-specific-tab" class="config-tab" type="button" role="tab" aria-selected="false" aria-controls="config-model-specific-panel" tabindex="-1">Model-specific</button>
    <button id="config-costs-tab" class="config-tab" type="button" role="tab" aria-selected="false" aria-controls="config-costs-panel" tabindex="-1">Model costs</button>
</div>
<section id="config-settings-panel" class="config-tab-panel" role="tabpanel" aria-labelledby="config-settings-tab" tabindex="0">
    <p id="config-settings-empty" class="muted" hidden>No settings are available.</p>
    <div class="config-table-wrap">
        <table class="config-table" aria-label="Configuration settings">
            <thead><tr><th scope="col">Parameter</th><th scope="col">Value</th><th scope="col">Scope</th><th scope="col">Action</th></tr></thead>
            <tbody id="config-settings-list"></tbody>
        </table>
    </div>
</section>
<section id="config-credentials-panel" class="config-tab-panel" role="tabpanel" aria-labelledby="config-credentials-tab" tabindex="0" hidden>
    <p class="config-help">Credentials let MAIA authenticate with external services. Values are masked in this list.</p>
    <p id="config-credentials-empty" class="muted" hidden>No credential parameters are available.</p>
    <div class="config-table-wrap">
        <table class="config-table" aria-label="External service credentials">
            <thead><tr><th scope="col">Parameter</th><th scope="col">Value</th><th scope="col">Scope</th><th scope="col">Action</th></tr></thead>
            <tbody id="config-credentials-list"></tbody>
        </table>
    </div>
    <details class="config-add-credential">
        <summary>Add credential</summary>
        <form id="config-credential-form" class="config-add-inline-form config-add-credential-form">
            <input id="config-credential-key" name="key" type="text" autocomplete="off" placeholder="<mcp_name>_token" aria-label="Credential parameter name" pattern="[a-z0-9_]+" required>
            <input id="config-credential-value" name="value" type="password" autocomplete="new-password" placeholder="Value" aria-label="Credential value" required>
            <button id="config-credential-save" type="submit">Add</button>
        </form>
    </details>
</section>
<section id="config-model-specific-panel" class="config-tab-panel" role="tabpanel" aria-labelledby="config-model-specific-tab" tabindex="0" hidden>
    <p id="config-model-specific-empty" class="muted" hidden>No model-specific parameters are configured.</p>
    <div class="config-table-wrap">
        <table class="config-table" aria-label="Model-specific configuration">
            <thead><tr><th scope="col">Parameter</th><th scope="col">Value</th><th scope="col">Scope</th><th scope="col">Action</th></tr></thead>
            <tbody id="config-model-specific-list"></tbody>
        </table>
    </div>
    <details class="config-add-model-setting">
        <summary>Add model-specific parameter</summary>
        <form id="config-model-specific-form" class="config-add-inline-form config-add-model-setting-form">
            <input id="config-model-specific-key" name="key" type="text" autocomplete="off" placeholder="file_handling_mode_model_name" aria-label="Model-specific parameter name" required>
            <input id="config-model-specific-value" name="value" type="text" autocomplete="off" placeholder="APPEND" aria-label="Model-specific parameter value" required>
            <button id="config-model-specific-save" type="submit">Add</button>
        </form>
    </details>
</section>
<section id="config-costs-panel" class="config-tab-panel" role="tabpanel" aria-labelledby="config-costs-tab" tabindex="0" hidden>
    <p class="config-help">Costs are in dollars per 1 million tokens.</p>
    <p id="config-costs-empty" class="muted" hidden>No model costs are configured.</p>
    <div class="config-table-wrap">
        <table class="config-table" aria-label="Model costs">
            <thead><tr><th scope="col">Parameter</th><th scope="col">Value</th><th scope="col">Scope</th><th scope="col">Action</th></tr></thead>
            <tbody id="config-costs-list"></tbody>
        </table>
    </div>
    <details class="config-add-cost">
        <summary>Add model costs</summary>
        <form id="config-cost-form" class="config-add-inline-form config-add-cost-form">
            <input id="config-cost-model" name="model" type="text" autocomplete="off" placeholder="Model name" aria-label="Model name" required>
            <input id="config-cost-input" name="input" type="number" min="0" step="any" placeholder="Input cost ($ per 1M tokens)" aria-label="Input cost in dollars per 1 million tokens">
            <input id="config-cost-output" name="output" type="number" min="0" step="any" placeholder="Output cost ($ per 1M tokens)" aria-label="Output cost in dollars per 1 million tokens">
            <button id="config-cost-save" type="submit">Add</button>
        </form>
    </details>
</section>
