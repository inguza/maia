<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 * Licensed under the GNU General Public License v3.0.
 */
?>
<section class="changes-panel" aria-labelledby="changes-heading">
    <header class="changes-header">
        <h2 id="changes-heading">Changes</h2>
        <button type="button" data-changes-action="refresh" aria-label="Refresh changes" title="Refresh changes">&#x21BB;</button>
    </header>
    <div class="changes-filters">
        <fieldset>
            <legend>State</legend>
            <div class="changes-filter-options" data-changes-filter="state">
                <label><input type="checkbox" value="pending" checked> Pending</label>
                <label><input type="checkbox" value="running" checked> Running</label>
                <label><input type="checkbox" value="applied"> Applied</label>
                <label><input type="checkbox" value="skipped"> Skipped</label>
                <label><input type="checkbox" value="finished"> Finished</label>
                <label><input type="checkbox" value="failed"> Failed</label>
            </div>
        </fieldset>
        <fieldset>
            <legend>Type</legend>
            <div class="changes-filter-options" data-changes-filter="type">
                <label><input type="checkbox" value="manual" checked> Manual</label>
                <label><input type="checkbox" value="patch" checked> Patch</label>
                <label><input type="checkbox" value="shell" checked> Shell</label>
                <label><input type="checkbox" value="action" checked> Action</label>
                <label><input type="checkbox" value="snippet" checked> Snippet</label>
                <label><input type="checkbox" value="text" checked> Text</label>
            </div>
        </fieldset>
    </div>
    <div class="changes-bulk-actions" role="group" aria-label="Bulk change actions">
        <span data-changes-role="selection-count" aria-live="polite">0 selected</span>
        <label class="visually-hidden" for="changes-bulk-state">State for selected changes</label>
        <select id="changes-bulk-state" data-changes-role="bulk-state" aria-label="State for selected changes">
            <option value="pending">Pending</option>
            <option value="running">Running</option>
            <option value="applied">Applied</option>
            <option value="skipped">Skipped</option>
            <option value="finished">Finished</option>
            <option value="failed">Failed</option>
        </select>
        <button type="button" data-changes-action="bulk-state" disabled>Set state</button>
        <button type="button" data-changes-action="bulk-delete" disabled>Delete selected</button>
    </div>
    <pre class="changes-status" data-changes-role="status" role="status" aria-live="polite"></pre>
    <div class="changes-list" data-changes-role="list" aria-live="polite"></div>
</section>
