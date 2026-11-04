<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title><?= \maia_escape_html($page->title()) ?></title>
    <?= $page->stylesheetTags() ?>
</head>
<body class="<?= \maia_escape_html($page->bodyClass()) ?>"
      data-maia-workspace="<?= \maia_escape_html($page->workspaceName()) ?>"
      data-maia-session="<?= \maia_escape_html($page->sessionName()) ?>">
    <script>
        window.MAIA_BASE_PATH = <?= json_encode(\maia_base_path(), JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) ?>;
    </script>
    <?= $page->renderComponent('sidebar') ?>
    <main class="app">
        <header class="topbar">
            <h1>MAIA: <span data-role="filesystem-location"></span> (<?= \maia_escape_html($page->sessionName() !== '' ? 'session ' . $page->sessionName() : 'workspace ' . $page->workspaceName()) ?>)</h1>
        </header>
        <?= $page->renderComponent('browser') ?>
        <div id="filesystem-error" class="error" role="alert" hidden></div>
    </main>
    <?= $page->scriptTags() ?>
</body>
</html>
