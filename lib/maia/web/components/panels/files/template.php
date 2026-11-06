<section class="known-files-panel">
    <header class="known-files-header">
        <h2>Files</h2>
        <button type="button" data-known-files-action="refresh" aria-label="Refresh known files">&#x21BB;</button>
    </header>
    <form class="known-files-add" data-known-files-form>
        <label class="visually-hidden" for="known-file-path">Add file paths, one per line, relative to the workspace root</label>
        <textarea id="known-file-path" rows="1" autocomplete="off" placeholder="Path(s), one per line, relative to workspace root"></textarea>
        <div class="known-files-completion" data-known-files-role="completion" role="listbox" hidden></div>
        <button type="submit">Add</button>
    </form>
    <p class="known-files-status" data-known-files-role="status" role="status"></p>
    <ul class="known-files-list" data-known-files-role="list"></ul>
</section>
