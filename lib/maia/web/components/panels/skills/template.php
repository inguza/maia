<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */
?>
<h2>Skills</h2>
<p id="skills-scope" class="muted">Home skill scope</p>
<div class="inline-form">
    <label class="visually-hidden" for="skill-pattern">Add skill pattern</label>
    <input id="skill-pattern" type="text" autocomplete="off" placeholder="Skill pattern, e.g. *">
    <button id="skill-pattern-add" type="button">Add</button>
</div>
<div class="panel-actions">
    <button id="skill-clear" type="button">Clear</button>
    <button id="skill-delete" type="button">Delete</button>
    <button id="skills-refresh" type="button">Refresh</button>
</div>
<p id="skills-status" class="status" role="status" aria-live="polite"></p>
<ul id="skill-pattern-list" class="item-list" aria-label="Allowed skill patterns"></ul>
<details>
    <summary>Available skills</summary>
    <ul id="available-skills-list" class="available-list available-resources-list" aria-label="Available skills">
        <li class="available-resource-heading">
            <span class="available-resource-name">Name - Description</span>
            <span>Allowed</span>
            <span>In memory</span>
        </li>
    </ul>
</details>
