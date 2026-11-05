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
    <p class="changes-status" data-changes-role="status" role="status" aria-live="polite"></p>
    <div class="changes-list" data-changes-role="list" aria-live="polite"></div>
</section>
