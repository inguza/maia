<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 */
?>
<div class="approvals-header">
    <h2>Approvals</h2>
    <button id="approvals-refresh" class="small-action" type="button" title="Refresh approvals" aria-label="Refresh approvals">&#x21BB;</button>
</div>
<p id="approvals-scope" class="muted">Approval scope</p>
<div class="inline-form">
    <label class="visually-hidden" for="approval-rule">Add approval rule</label>
    <input id="approval-rule" type="text" autocomplete="off" placeholder="Rule, e.g. logs/*:append">
    <button id="approval-rule-add" type="button">Add</button>
</div>
<div class="panel-actions">
    <button id="approval-clear" type="button" title="Clear rules in this scope; inherited rules will be masked.">Clear</button>
    <button id="approval-delete" type="button" title="Delete rules in this scope; inherited rules will apply." hidden>Delete</button>
</div>
<p id="approvals-status" class="status" role="status" aria-live="polite"></p>
<ul id="approval-rule-list" class="item-list" aria-label="Approval rules"></ul>
