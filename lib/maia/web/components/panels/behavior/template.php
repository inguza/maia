<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */
?>
<h2>Behavior</h2>
<p id="behavior-source" class="muted" aria-live="polite">Open this panel to load behavior settings.</p>
<label class="behavior-label" for="behavior-text">How Maia should respond</label>
<textarea id="behavior-text" rows="12" spellcheck="false" disabled></textarea>
<div class="panel-actions behavior-actions">
    <button id="behavior-reset" type="button" title="Remove this scope's behavior version" aria-label="Remove this scope's behavior version" hidden>Delete</button>
    <button id="behavior-save" type="button" disabled>Save</button>
</div>
<p id="behavior-status" class="status" role="status" aria-live="polite"></p>
