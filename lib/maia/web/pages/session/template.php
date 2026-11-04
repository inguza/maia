<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title><?= \maia_escape_html($page->title()) ?></title>
    <?= $page->stylesheetTags() ?>
</head>
<body class="<?= \maia_escape_html($page->bodyClass()) ?>" data-maia-session="<?= \maia_escape_html($page->sessionName()) ?>"<?= $page->workspaceName() !== '' ? ' data-maia-workspace="' . \maia_escape_html($page->workspaceName()) . '"' : '' ?>>
    <script>window.MAIA_BASE_PATH = <?= json_encode(\maia_base_path(), JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) ?>;</script>
    <?= $page->renderComponent('sidebar') ?>
    <main class="app">
        <header class="topbar"><h1><?= \maia_escape_html($page->title()) ?></h1></header>
        <div id="session-error" class="session-error" role="alert" hidden></div>
        <?= $page->renderComponent('history') ?>
        <?= $page->renderComponent('composer') ?>
    </main>
    <?= $page->scriptTags() ?>
</body>
</html>
