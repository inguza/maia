<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */
?>
<h2>Tools</h2>
<p id="tools-scope" class="muted">Home tool scope</p>
<div class="inline-form">
    <label class="visually-hidden" for="tool-pattern">Add tool pattern</label>
    <input id="tool-pattern" type="text" autocomplete="off" placeholder="Tool pattern, e.g. * or *:write">
    <button id="tool-pattern-add" type="button">Add</button>
</div>
<div class="panel-actions">
    <button id="tool-clear" type="button">Clear</button>
    <button id="tool-delete" type="button">Delete</button>
    <button id="tools-refresh" type="button">Refresh</button>
</div>
<p id="tools-status" class="status" role="status" aria-live="polite"></p>
<ul id="tool-pattern-list" class="item-list" aria-label="Allowed tool patterns"></ul>
<details>
    <summary>Available tools</summary>
    <ul id="available-tools-list" class="available-list" aria-label="Available tools"></ul>
</details>
