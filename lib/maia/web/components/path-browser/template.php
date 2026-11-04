<section class="path-browser<?= $sessionTarget !== '' ? ' session-browser' : '' ?>" data-workspace="<?= $workspaceName ?>" data-relative-path="<?= $relativePath ?>" data-uri-root="<?= $uriRoot ?>" data-root-query="<?= $rootQuery ?>" data-session-target="<?= $sessionTarget ?>" data-initial-file="<?= $initialFile ?>" data-file-only="<?= $fileOnly ?>">
    <div class="path-browser-navigation">
        <nav class="path-browser-breadcrumb" aria-label="Filesystem path" data-role="breadcrumb"></nav>
        <div class="path-browser-toolbar">
            <div class="path-browser-navigation-controls">
                <button type="button" data-action="up" aria-label="Go up" title="Go up">&#x2191;</button>
                <button type="button" data-action="back" aria-label="Back to directory" title="Back to directory" hidden>Back</button>
                <button type="button" data-action="refresh" aria-label="Refresh" title="Refresh">&#x21BB;</button>
                <button type="button" data-action="edit" aria-label="Edit file" title="Edit file" hidden>Edit</button>
                <button type="button" data-action="save" aria-label="Save file" title="Save file" hidden>Save</button>
                <button type="button" data-action="cancel" aria-label="Cancel editing" title="Cancel editing" hidden>Cancel</button>
            </div>
            <div class="path-browser-selection-actions" aria-label="Actions for selected files">
                <button type="button" data-action="copy-selected" disabled aria-label="Copy selected paths" title="Copy selected paths">Copy</button>
                <button type="button" data-action="move-selected" disabled aria-label="Move selected paths" title="Move selected paths">Move</button>
                <button type="button" data-action="delete-selected" disabled aria-label="Delete selected files" title="Delete selected files">Delete</button>
                <button type="button" data-action="add-selected" aria-label="Add selected files to session" title="Add selected files to session"<?= $sessionTarget === '' ? ' hidden' : '' ?>>Add selected</button>
            </div>
            <div class="path-browser-file-controls">
                <button type="button" data-action="new-directory" aria-label="Create directory" title="Create directory">New folder</button>
                <button type="button" data-action="new-file" aria-label="Create file" title="Create file">New file</button>
                <input type="file" data-role="upload-input" multiple hidden>
                <button type="button" data-action="upload" aria-label="Upload files" title="Upload files">Upload</button>
            </div>
        </div>
    </div>
    <p class="path-browser-status" role="status" data-role="status"></p>
    <ul class="path-browser-list" data-role="list"></ul>
    <section class="path-browser-viewer" data-role="viewer" hidden>
        <header class="path-browser-viewer-header">
            <strong data-role="viewer-title" hidden></strong>
            <div class="path-browser-viewer-actions">
                <span data-role="session-target-fixed" hidden></span>
                <div data-role="session-target-control" class="path-browser-session-target" hidden>
                    <label for="path-browser-session-target">Target session</label>
                    <div class="path-browser-session-target-input">
                        <input id="path-browser-session-target" data-role="session-target" type="text"
                               autocomplete="off" placeholder="Select a session"
                               role="combobox" aria-autocomplete="list" aria-haspopup="listbox"
                               aria-controls="path-browser-session-target-menu" aria-expanded="false">
                        <div id="path-browser-session-target-menu" data-role="session-target-menu"
                             class="path-browser-session-target-menu" role="listbox" hidden></div>
                    </div>
                    <span data-role="session-target-status" role="status"></span>
                </div>
                <button type="button" data-action="clear-line-selection" hidden>Clear selection</button>
                <button type="button" data-action="add-viewed" hidden disabled>Add file</button>
            </div>
        </header>
        <div class="path-browser-viewer-content" data-role="viewer-content"></div>
        <textarea data-role="editor" spellcheck="false" hidden></textarea>
    </section>
</section>
