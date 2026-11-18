<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */
?>
<button id="sidebar-toggle" class="sidebar-toggle" type="button"
        aria-label="Open navigation" aria-expanded="false" aria-controls="sidebar">&#x2630;</button>
<aside id="sidebar" class="sidebar" aria-label="MAIA navigation" aria-hidden="true">
    <header class="sidebar-header">
        <a class="brand" href="<?= $homeUrl ?>">MAIA</a>
        <button id="sidebar-refresh" class="sidebar-refresh" type="button" aria-label="Refresh sessions and workspaces" title="Refresh sessions and workspaces">&#x21BB;</button>
        <button id="sidebar-close" class="sidebar-close" type="button" aria-label="Close navigation">&#x00D7;</button>
    </header>
    <p id="sidebar-error" class="error" role="alert" hidden></p>

    <section class="sidebar-section">
        <div class="sidebar-section-heading">
            <h2>Sessions</h2>
            <div class="sidebar-section-actions">
                <button id="session-group-create" class="sidebar-small-button sidebar-icon-button" type="button" aria-label="Create session group" title="Create session group"></button>
                <button id="session-create-top" class="sidebar-small-button sidebar-icon-button" type="button" aria-label="Create session" title="Create session"></button>
            </div>
        </div>
        <form id="session-search" class="resource-search">
            <label class="visually-hidden" for="session-search-input">Find or create session</label>
            <input id="session-search-input" type="search" autocomplete="off" placeholder="Session name">
            <button type="submit" aria-label="Search or open session">&#x1F50D;</button>
            <button id="session-create" type="button" aria-label="Create session" hidden>+</button>
        </form>
        <div id="session-list" class="sidebar-list sidebar-session-groups" aria-label="MAIA sessions"></div>
        <p id="session-list-placeholder" class="sidebar-placeholder" role="status">Loading sessions&hellip;</p>
    </section>

    <section class="sidebar-section">
        <h2>Workspaces</h2>
        <form id="workspace-search" class="resource-search">
            <label class="visually-hidden" for="workspace-search-input">Find or create workspace</label>
            <input id="workspace-search-input" type="search" autocomplete="off" placeholder="Workspace name">
            <button type="submit" aria-label="Search or open workspace">&#x1F50D;</button>
            <button id="workspace-create" type="button" aria-label="Create workspace" hidden>+</button>
        </form>
        <ul id="workspace-list" class="sidebar-list" aria-label="MAIA workspaces"></ul>
        <p id="workspace-list-placeholder" class="sidebar-placeholder" role="status">Loading workspaces&hellip;</p>
    </section>

</aside>
<dialog id="sidebar-session-settings" class="sidebar-dialog">
    <form id="sidebar-session-settings-form" method="dialog">
        <h2 id="sidebar-session-settings-title">Session settings</h2>
        <label>Profile<select id="sidebar-setting-profile"></select></label>
        <label>Workspace<select id="sidebar-setting-workspace"></select></label>
        <label>Filesets<select id="sidebar-setting-filesets" multiple></select></label>
        <label>Extra send filesets<select id="sidebar-setting-extra-filesets" multiple></select></label>
        <p id="sidebar-session-settings-status" role="status"></p>
        <div class="sidebar-dialog-actions">
            <button class="action-cancel" type="submit" value="cancel">Close</button>
            <button id="sidebar-session-settings-save" class="action-normal" type="submit" value="save">Save</button>
        </div>
    </form>
</dialog>
<dialog id="sidebar-session-move-dialog" class="sidebar-dialog">
    <form id="sidebar-session-move-form" method="dialog">
        <h2 id="sidebar-session-move-title">Move</h2>
        <label>Group<select id="sidebar-session-move-group"></select></label>
        <div class="sidebar-dialog-actions">
            <button class="action-cancel" type="submit" value="cancel">Cancel</button>
            <button class="action-normal" type="submit" value="move">Move</button>
        </div>
    </form>
</dialog>
<dialog id="sidebar-session-group-create-dialog" class="sidebar-dialog">
    <form id="sidebar-session-group-create-form" method="dialog">
        <h2 id="sidebar-session-group-create-title">Create group</h2>
        <p id="sidebar-session-group-create-message"></p>
        <label id="sidebar-session-group-create-label">Group name
            <input id="sidebar-session-group-create-name" type="text" autocomplete="off">
        </label>
        <div class="sidebar-dialog-actions">
            <button class="action-cancel" type="submit" value="cancel">Cancel</button>
            <button class="action-normal" type="submit" value="create">Create</button>
        </div>
    </form>
</dialog>
<dialog id="sidebar-workspace-directory-dialog" class="sidebar-dialog">
    <form method="dialog">
        <h2>Create workspace directory?</h2>
        <p id="sidebar-workspace-directory-message"></p>
        <div class="sidebar-dialog-actions">
            <button class="action-cancel" value="cancel">Cancel</button>
            <button class="action-normal" value="create">Create</button>
        </div>
    </form>
</dialog>
<dialog id="sidebar-input-dialog" class="sidebar-dialog">
    <form method="dialog">
        <h2 id="sidebar-input-title">Action</h2>
        <label id="sidebar-input-label" for="sidebar-input-value">Value
            <input id="sidebar-input-value" type="text" autocomplete="off">
        </label>
        <div class="sidebar-dialog-actions">
            <button class="action-cancel" type="submit" value="cancel">Cancel</button>
            <button id="sidebar-input-confirm" class="action-normal" type="submit" value="confirm">OK</button>
        </div>
    </form>
</dialog>
<dialog id="sidebar-confirm-dialog" class="sidebar-dialog">
    <form method="dialog">
        <h2 id="sidebar-confirm-title">Confirm</h2>
        <p id="sidebar-confirm-message"></p>
        <div class="sidebar-dialog-actions">
            <button class="action-cancel" type="submit" value="cancel">Cancel</button>
            <button id="sidebar-confirm-action" class="action-check" type="submit" value="confirm">Remove</button>
        </div>
    </form>
</dialog>
<button id="sidebar-backdrop" class="sidebar-backdrop" type="button"
        aria-label="Close navigation" tabindex="-1" hidden></button>
