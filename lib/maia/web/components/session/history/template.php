<section class="session-history" aria-label="Session conversation">
    <div class="session-history-toolbar">
        <div class="session-history-loading-controls">
            <button type="button" data-history-action="earlier" hidden title="Load previous turn(s)" aria-label="Load previous turns">&#x2B06;</button>
            <label data-history-role="turn-count-control" hidden>
                <input type="text" inputmode="numeric" maxlength="3" value="1" data-history-role="turn-count" aria-label="Number of previous turns to load">
                turns
            </label>
            <button type="button" data-history-action="all" hidden title="Load entire history" aria-label="Load entire history">&#x21C8;</button>
            <span class="session-history-remaining" data-history-role="remaining" hidden></span>
        </div>
        <div class="session-history-menu-controls">
            <span data-history-role="tool-view-menu"></span>
            <span data-history-role="session-menu"></span>
        </div>
    </div>
    <p class="session-history-status" role="status" aria-live="polite" data-history-role="status"></p>
    <div class="session-history-items" aria-live="polite" data-history-role="items"></div>

    <dialog class="session-history-dialog" data-history-dialog="edit">
        <form method="dialog" data-history-form="edit">
            <h2>Edit history entry</h2>
            <textarea data-history-role="edit-content" required></textarea>
            <p class="session-history-dialog-error" role="alert" data-history-role="edit-error" hidden></p>
            <div class="session-history-dialog-actions">
                <button type="submit" value="cancel">Cancel</button>
                <button type="submit" value="save" data-history-action="save-edit">Save</button>
            </div>
        </form>
    </dialog>

    <dialog class="session-history-dialog" data-history-dialog="settings">
        <form method="dialog" data-history-form="settings">
            <h2>Session settings</h2>
            <div class="session-history-settings-grid">
                <label>Profile<select data-history-role="setting-profile"></select></label>
                <label>Workspace<select data-history-role="setting-workspace"></select></label>
                <label>Filesets<select data-history-role="setting-filesets" multiple></select></label>
                <label>Extra send filesets<select data-history-role="setting-extra-filesets" multiple></select></label>
            </div>
            <p class="session-history-dialog-error" role="status" data-history-role="settings-status"></p>
            <div class="session-history-dialog-actions">
                <button type="submit" value="cancel">Cancel</button>
                <button type="submit" value="save" data-history-action="save-settings">Save</button>
            </div>
        </form>
    </dialog>

    <dialog class="session-history-dialog" data-history-dialog="rename">
        <form method="dialog" data-history-form="rename">
            <h2>Rename session</h2>
            <label>New session name<input data-history-role="rename-name" type="text" pattern="[A-Za-z0-9_.%+\\-]+" required autocomplete="off"></label>
            <p class="session-history-dialog-error" role="alert" data-history-role="rename-error" hidden></p>
            <div class="session-history-dialog-actions">
                <button type="submit" value="cancel">Cancel</button>
                <button type="submit" value="rename" data-history-action="save-rename">Rename</button>
            </div>
        </form>
    </dialog>

    <dialog class="session-history-dialog" data-history-dialog="copy">
        <form method="dialog" data-history-form="copy">
            <h2>Copy session</h2>
            <label>New session name<input data-history-role="copy-name" type="text" pattern="[A-Za-z0-9_.%+\\-]+" required autocomplete="off"></label>
            <p class="session-history-dialog-error" role="alert" data-history-role="copy-error" hidden></p>
            <div class="session-history-dialog-actions">
                <button type="submit" value="cancel">Cancel</button>
                <button type="submit" value="copy" data-history-action="save-copy">Copy</button>
            </div>
        </form>
    </dialog>
</section>
