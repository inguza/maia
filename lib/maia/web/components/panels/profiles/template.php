<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */
?>
<section class="profiles-manager" data-profiles-manager data-scope="<?= $scope ?>" data-workspace="<?= $workspaceName ?>">
    <div class="profiles-toolbar">
        <p class="profiles-scope"><?= $scopeLabel ?></p>
        <button type="button" data-profiles-refresh>Refresh</button>
    </div>
    <form class="profiles-create" data-profile-create-form>
        <label for="profiles-new-name">Name</label>
        <input id="profiles-new-name" name="name" type="text" required pattern="[A-Za-z0-9_.%+\-]+" autocomplete="off">
        <label for="profiles-new-description">Description</label>
        <input id="profiles-new-description" name="description" type="text">
        <button type="submit" data-profile-create> Create profile</button>
    </form>
    <p class="profiles-status" role="status" data-profiles-status></p>
    <ul class="profiles-list" aria-label="Profiles in this scope" data-profiles-list></ul>

    <dialog class="profiles-settings-dialog" data-profile-settings-dialog>
        <form data-profile-settings-form>
            <h2 data-profile-settings-title>Profile settings</h2>
            <label for="profiles-settings-description">Description</label>
            <input id="profiles-settings-description" name="description" type="text">
            <p class="profiles-settings-scope" data-profile-settings-scope></p>
            <p class="profiles-status" role="status" data-profile-settings-status></p>
            <div class="profiles-dialog-actions">
                <button type="button" data-profile-settings-cancel>Close</button>
                <button type="submit" data-profile-settings-save>Save</button>
            </div>
        </form>
    </dialog>
</section>
