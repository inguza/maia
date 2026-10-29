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
        aria-label="Open navigation" aria-expanded="false" aria-controls="sidebar">â°</button>
<aside id="sidebar" class="sidebar" aria-label="MAIA navigation" aria-hidden="true">
    <header class="sidebar-header">
        <a class="brand" href="<?= $homeUrl ?>">MAIA</a>
        <button id="sidebar-close" class="sidebar-close" type="button" aria-label="Close navigation">Ã</button>
    </header>

    <section class="sidebar-section">
        <h2>Sessions</h2>
        <form id="session-search" class="resource-search">
            <label class="visually-hidden" for="session-search-input">Find or create session</label>
            <input id="session-search-input" type="search" autocomplete="off" placeholder="Session name">
            <button type="submit" aria-label="Open or create session">Go</button>
        </form>
        <ul id="session-list" class="sidebar-list" aria-label="MAIA sessions"></ul>
        <p id="session-list-placeholder" class="sidebar-placeholder" role="status">Loading sessionsâ¦</p>
    </section>

    <section class="sidebar-section">
        <h2>Workspaces</h2>
        <form id="workspace-search" class="resource-search">
            <label class="visually-hidden" for="workspace-search-input">Find or create workspace</label>
            <input id="workspace-search-input" type="search" autocomplete="off" placeholder="Workspace name">
            <button type="submit" aria-label="Open or create workspace">Go</button>
        </form>
        <ul id="workspace-list" class="sidebar-list" aria-label="MAIA workspaces"></ul>
        <p id="workspace-list-placeholder" class="sidebar-placeholder" role="status">Loading workspacesâ¦</p>
    </section>

    <section class="sidebar-section">
        <h2>Profiles</h2>
        <form id="profile-search" class="resource-search">
            <label class="visually-hidden" for="profile-search-input">Find or create profile</label>
            <input id="profile-search-input" type="search" autocomplete="off" placeholder="Profile name">
            <button type="submit" aria-label="Open or create profile">Go</button>
        </form>
        <ul id="profile-list" class="sidebar-list" aria-label="MAIA profiles"></ul>
        <p id="profile-list-placeholder" class="sidebar-placeholder" role="status">Loading profilesâ¦</p>
    </section>
</aside>
<button id="sidebar-backdrop" class="sidebar-backdrop" type="button"
        aria-label="Close navigation" tabindex="-1" hidden></button>
