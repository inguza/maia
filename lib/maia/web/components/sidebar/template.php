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
        <button id="sidebar-close" class="sidebar-close" type="button" aria-label="Close navigation">&#x00D7;</button>
    </header>

    <section class="sidebar-section">
        <h2>Sessions</h2>
        <form id="session-search" class="resource-search">
            <label class="visually-hidden" for="session-search-input">Find or create session</label>
            <input id="session-search-input" type="search" autocomplete="off" placeholder="Session name">
            <button type="submit" aria-label="Search or open session">&#x1F50D;</button>
            <button id="session-create" type="button" aria-label="Create session" hidden>+</button>
        </form>
        <ul id="session-list" class="sidebar-list" aria-label="MAIA sessions"></ul>
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

    <section class="sidebar-section">
        <h2>Profiles</h2>
        <form id="profile-search" class="resource-search">
            <label class="visually-hidden" for="profile-search-input">Find or create profile</label>
            <input id="profile-search-input" type="search" autocomplete="off" placeholder="Profile name">
            <button type="submit" aria-label="Search or open profile">&#x1F50D;</button>
            <button id="profile-create" type="button" aria-label="Create profile" hidden>+</button>
        </form>
        <ul id="profile-list" class="sidebar-list" aria-label="MAIA profiles"></ul>
        <p id="profile-list-placeholder" class="sidebar-placeholder" role="status">Loading profiles&hellip;</p>
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
            <button type="submit" value="cancel">Close</button>
            <button id="sidebar-session-settings-save" type="submit" value="save">Save</button>
        </div>
    </form>
</dialog>
<button id="sidebar-backdrop" class="sidebar-backdrop" type="button"
        aria-label="Close navigation" tabindex="-1" hidden></button>
