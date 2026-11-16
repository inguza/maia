<?php
/* Copyright (c) 2026 Ola Lundqvist <ola@inguza.com> */
?>
<section class="tasks-panel" aria-labelledby="tasks-heading">
    <header class="tasks-header">
        <h2 id="tasks-heading">Tasks</h2>
        <div class="tasks-header-actions">
            <button type="button" class="tasks-create-toggle" data-tasks-action="toggle-create" aria-label="Create task" title="Create task" aria-expanded="false">+</button>
            <button type="button" data-tasks-action="refresh" aria-label="Refresh tasks" title="Refresh tasks">&#x21BB;</button>
        </div>
    </header>
    <form class="tasks-create-form" data-tasks-form hidden>
        <div class="tasks-create-options">
            <label class="visually-hidden" for="tasks-create-scope">Task scope</label>
            <select id="tasks-create-scope" data-tasks-role="create-scope">
                <option value="session">Private to this session</option>
                <option value="workspace">Shared with workspace</option>
                <option value="profile">Shared with profile</option>
            </select>
            <button type="submit">Create</button>
        </div>
        <label class="visually-hidden" for="tasks-create-description">New task description</label>
        <textarea id="tasks-create-description" rows="2" placeholder="Describe a task"></textarea>
    </form>
    <hr class="tasks-divider">
    <p class="tasks-status" data-tasks-role="status" role="status" aria-live="polite"></p>
    <div class="tasks-list-controls" aria-label="Task list display controls">
        <button type="button" data-tasks-action="expand-all">Expand all</button>
        <button type="button" data-tasks-action="collapse-all">Collapse all</button>
    </div>
    <div class="tasks-list" data-tasks-role="list" aria-live="polite"></div>
</section>
