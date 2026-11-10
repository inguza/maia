<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title><?= \maia_escape_html($page->title()) ?></title>
    <?= $page->stylesheetTags() ?>
</head>
<body class="change-page" data-maia-session="<?= \maia_escape_html($page->sessionName()) ?>"<?= $page->workspaceName() !== '' ? ' data-maia-workspace="' . \maia_escape_html($page->workspaceName()) . '"' : '' ?> data-maia-change-id="<?= \maia_escape_html($page->changeId()) ?>">
    <script>window.MAIA_BASE_PATH = <?= json_encode(\maia_base_path(), JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) ?>;</script>
    <?= $page->renderComponent('sidebar') ?>
    <main class="change-page-main">
        <a class="change-page-back" href="<?= \maia_escape_html(\maia_base_path() . '/session/' . rawurlencode($page->sessionName())) ?>">&larr; Back to session</a>
        <h1>Change <code><?= \maia_escape_html($page->changeId()) ?></code></h1>
        <p class="change-page-meta" id="change-page-meta"></p>
        <div class="change-page-controls" id="change-page-controls" aria-label="Change actions"></div>
        <p class="change-page-status" id="change-page-status" role="status" aria-live="polite">Loading change...</p>
        <pre id="change-page-detail" class="change-page-detail"></pre>
    </main>
    <?= $page->scriptTags() ?>
</body>
</html>
