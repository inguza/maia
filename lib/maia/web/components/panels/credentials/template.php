<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */
?>
<h2>Access tokens</h2>
<p id="credentials-description" class="muted">Tokens that grant access to this MAIA web interface. These are separate from credentials MAIA uses to access external services.</p>
<div class="inline-form">
    <label class="visually-hidden" for="credential-name">New access token name (optional)</label>
    <input id="credential-name" type="text" autocomplete="off" placeholder="Token name (optional)">
    <button id="credential-create" type="button">Create</button>
</div>
<p id="credentials-status" class="status" role="status" aria-live="polite"></p>
<ul id="credential-list" class="item-list" aria-label="MAIA access tokens"></ul>
