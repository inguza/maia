<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */
?>
<button id="profile-settings-toggle" class="profile-settings-toggle" type="button"
        aria-label="Profile settings" title="Profile settings">&#x2699;&#xFE0E;</button>
<dialog id="profile-settings-dialog" class="profile-settings-dialog">
    <form id="profile-settings-form" method="dialog">
        <h2 id="profile-settings-title">Profile settings</h2>
        <label for="profile-settings-description">
            Description
            <input id="profile-settings-description" name="description" type="text">
        </label>
        <p id="profile-settings-scope" class="profile-settings-scope"></p>
        <p id="profile-settings-status" class="profile-settings-status" role="status"></p>
        <div class="profile-settings-actions">
            <button type="submit" value="cancel">Cancel</button>
            <button id="profile-settings-save" type="submit" value="save">Save</button>
        </div>
    </form>
</dialog>
