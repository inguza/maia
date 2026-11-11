<form class="session-composer" data-session-composer>
    <label for="session-message">Continue in session: <span data-composer-session></span></label>
    <textarea id="session-message" name="message" required autofocus></textarea>
    <div class="session-composer-actions">
        <p class="session-composer-status" role="status" data-composer-status></p>
        <button type="button" class="session-composer-usage" data-composer-usage aria-haspopup="dialog">
            <span data-composer-usage-today>Today: --</span>
        </button>
        <button type="button" class="session-composer-cancel" data-composer-cancel hidden aria-label="Cancel active send" title="Cancel active send">
            <span data-composer-cancel-icon aria-hidden="true">&#x23F9;</span>
            <span class="spinner" data-composer-cancel-spinner aria-hidden="true" hidden></span>
        </button>
        <button type="submit" data-composer-send>Send</button>
    </div>
</form>
    <dialog class="session-composer-usage-dialog" data-composer-usage-dialog>
    <div class="session-composer-usage-dialog-content">
        <header class="session-composer-usage-dialog-header">
            <h2>Token usage</h2>
            <button type="button" class="session-composer-usage-close" data-composer-usage-close aria-label="Close usage details">&times;</button>
        </header>
        <section data-usage-section="session">
            <h3 data-usage-detail="session-title">Session total</h3>
            <dl>
                <dt>Input</dt><dd data-usage-detail="session-input">--</dd>
                <dt>Cached input</dt><dd data-usage-detail="session-cached">--</dd>
                <dt>Output</dt><dd data-usage-detail="session-output">--</dd>
                <dt>Reasoning</dt><dd data-usage-detail="session-reasoning">--</dd>
            </dl>
        </section>
        <section data-usage-section="today">
            <h3>Today</h3>
            <dl>
                <dt>Input</dt><dd data-usage-detail="today-input">--</dd>
                <dt>Cached input</dt><dd data-usage-detail="today-cached">--</dd>
                <dt>Output</dt><dd data-usage-detail="today-output">--</dd>
                <dt>Reasoning</dt><dd data-usage-detail="today-reasoning">--</dd>
            </dl>
        </section>
        <section>
            <h3>Latest response</h3>
            <p data-usage-detail="latest-info">No usage recorded yet.</p>
            <dl>
                <dt>Input</dt><dd data-usage-detail="latest-input">--</dd>
                <dt>Cached input</dt><dd data-usage-detail="latest-cached">--</dd>
                <dt>Output</dt><dd data-usage-detail="latest-output">--</dd>
                <dt>Reasoning</dt><dd data-usage-detail="latest-reasoning">--</dd>
            </dl>
        </section>
    </div>
</dialog>
