<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 */
?>
<header class="panel-content-header">
    <h2>Instructions</h2>
    <button id="instructions-refresh" class="small-action" type="button" title="Refresh instructions" aria-label="Refresh instructions">&#x21BB;</button>
</header>
<p id="instructions-scope" class="muted">Instruction scope</p>
<div class="inline-form">
    <label class="visually-hidden" for="instruction-pattern">Add instruction name or pattern</label>
    <input id="instruction-pattern" type="text" autocomplete="off" placeholder="Instruction name or pattern, e.g. coding-*">
    <button id="instruction-pattern-add" type="button">Add</button>
</div>
<div class="panel-actions">
    <button id="instruction-clear" type="button" title="Clear selections in this scope; inherited selections will be masked.">Clear</button>
    <button id="instruction-delete" type="button" title="Delete selections in this scope; inherited selections will apply." hidden>Delete</button>
    <button id="instruction-remove-selected" class="remove-selected" type="button" hidden>Remove selected</button>
</div>
<p id="instructions-status" class="status" role="status" aria-live="polite"></p>
<ul id="instruction-pattern-list" class="item-list" aria-label="Selected instruction patterns"></ul>
<details>
    <summary>Available instructions</summary>
    <ul id="available-instructions-list" class="available-list" aria-label="Available instructions">
        <li class="available-resource-heading">
            <span>Instruction and autoload rules</span>
            <span>Selection</span>
        </li>
    </ul>
</details>
