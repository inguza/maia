<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title><?= \maia_escape_html($page->title()) ?></title>
    <?= $page->stylesheetTags() ?>
</head>
<body class="<?= \maia_escape_html($page->bodyClass()) ?>"
      data-maia-workspace="<?= \maia_escape_html($page->workspaceName()) ?>">
    <script>
        window.MAIA_BASE_PATH = <?= json_encode(\maia_base_path(), JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) ?>;
    </script>
    <?= $page->renderComponent('sidebar') ?>
    <main class="app">
        <header class="topbar">
            <h1>MAIA: <span data-role="filesystem-location"></span> (workspace <?= \maia_escape_html($page->workspaceName()) ?>)</h1>
        </header>
        <div class="panel-group workspace-panels" aria-label="Workspace panels">
            <?= $page->renderComponent('files') ?>
            <?= $page->renderComponent('skills') ?>
            <?= $page->renderComponent('tools') ?>
            <?= $page->renderComponent('settings') ?>
            <?= $page->renderComponent('profiles') ?>
        </div>
        <?= $page->renderComponent('browser') ?>
        <div id="home-error" class="error" role="alert" hidden></div>
    </main>
    <?= $page->scriptTags() ?>
</body>
</html>
