<section class="known-files-panel">
    <header class="known-files-header">
        <h2>Files</h2>
        <button type="button" data-known-files-action="refresh" aria-label="Refresh known files">&#x21BB;</button>
    </header>
    <form class="known-files-add" data-known-files-form>
        <label class="visually-hidden" for="known-file-path">File paths to add, one per line, or a pattern to remove</label>
        <textarea id="known-file-path" rows="1" autocomplete="off" placeholder="Path(s), one per line, relative to workspace root"></textarea>
        <div class="known-files-completion" data-known-files-role="completion" role="listbox" hidden></div>
        <button type="button" data-known-files-action="remove-pattern">Remove</button>
        <button type="submit">Add</button>
    </form>
    <div class="known-files-actions">
        <button type="button" data-known-files-action="clear" title="Clear file list." aria-label="Clear file list.">Clear</button>
    </div>
    <p class="known-files-status" data-known-files-role="status" role="status"></p>
    <ul class="known-files-list" data-known-files-role="list"></ul>
</section>
