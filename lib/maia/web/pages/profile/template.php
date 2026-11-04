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
<body class="<?= \maia_escape_html($page->bodyClass()) ?>"
      data-maia-profile="<?= \maia_escape_html($page->profileName()) ?>"<?php if ($page->workspaceName() !== ''): ?>
      data-maia-workspace="<?= \maia_escape_html($page->workspaceName()) ?>"<?php else: ?>
      data-maia-home="home"<?php endif; ?>>
    <?= $page->renderComponent('sidebar') ?>
    <main class="app">
        <header class="topbar">
            <h1>profile: <?= \maia_escape_html($page->profileName()) ?></h1>
            <?= $page->renderComponent('profile-settings') ?>
        </header>
        <div class="panel-group profile-panels" aria-label="Profile settings">
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
