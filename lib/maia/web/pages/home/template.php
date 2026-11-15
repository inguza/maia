<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */
?>
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title><?= \maia_escape_html($page->title()) ?></title>
<?= $page->stylesheetTags() ?>
</head>
<body class="<?= \maia_escape_html($page->bodyClass()) ?>" data-maia-home="home">
    <?= $page->renderComponent('sidebar') ?>
    <main class="app">
        <header class="topbar">
            <h1>home</h1>
        </header>
        <section class="home-usage" data-home-usage aria-labelledby="home-usage-title">
            <h2 id="home-usage-title">Token usage</h2>
            <p class="home-usage-status" data-home-usage-status role="status" aria-live="polite">Loading usage&hellip;</p>
            <div class="home-usage-periods">
                <section aria-labelledby="home-usage-total-title">
                    <h3 id="home-usage-total-title">All sessions</h3>
                    <dl>
                        <dt>Input</dt><dd data-home-usage="home-input">&mdash;</dd>
                        <dt>Cached input</dt><dd data-home-usage="home-cached">&mdash;</dd>
                        <dt>Output</dt><dd data-home-usage="home-output">&mdash;</dd>
                        <dt>Reasoning</dt><dd data-home-usage="home-reasoning">&mdash;</dd>
                    </dl>
                </section>
                <section aria-labelledby="home-usage-today-title">
                    <h3 id="home-usage-today-title">Today</h3>
                    <dl>
                        <dt>Input</dt><dd data-home-usage="today-input">&mdash;</dd>
                        <dt>Cached input</dt><dd data-home-usage="today-cached">&mdash;</dd>
                        <dt>Output</dt><dd data-home-usage="today-output">&mdash;</dd>
                        <dt>Reasoning</dt><dd data-home-usage="today-reasoning">&mdash;</dd>
                    </dl>
                </section>
            </div>
        </section>
        <div class="home-panels" aria-label="Home tools">
            <?= $page->renderComponent('profiles') ?>
            <?= $page->renderComponent('credentials') ?>
            <?= $page->renderComponent('behavior') ?>
            <?= $page->renderComponent('configuration') ?>
            <?= $page->renderComponent('skills') ?>
            <?= $page->renderComponent('tools') ?>
        </div>
        <p id="home-error" class="error" role="alert" hidden></p>
    </main>
    <script>
        window.MAIA_BASE_PATH = <?= json_encode(\maia_base_path(), JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) ?>;
    </script>
<?= $page->scriptTags() ?>
</body>
</html>
