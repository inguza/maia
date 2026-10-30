<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */
?>
<section class="expandable-panel" data-expandable-panel>
    <button class="panel-toggle" id="<?= $safeId ?>-toggle" type="button"
            aria-expanded="false" aria-controls="<?= $safeId ?>">
        <?= $safeLabel ?> <span aria-hidden="true">&#x25B8;</span>
    </button>
    <div class="panel-content" id="<?= $safeId ?>" hidden>
        <?= $content ?>
    </div>
</section>
