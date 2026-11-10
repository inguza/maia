<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 * Licensed under the GNU General Public License v3.0.
 */

declare(strict_types=1);

namespace Maia\Web\Pages\Change;

use Maia\Web\Components\Sidebar\SidebarComponent;
use Maia\Web\Core\Page;
use Maia\Web\Core\Script;
use Maia\Web\Core\Stylesheet;

require_once __DIR__ . '/../common.php';
require_once dirname(__DIR__, 2) . '/core/page.php';
require_once dirname(__DIR__, 2) . '/components/sidebar/component.php';
require_once dirname(__DIR__, 2) . '/api/web.php';

final class ChangePage extends Page
{
    public function __construct(
        private readonly string $sessionName,
        private readonly string $workspaceName,
        private readonly string $changeId
    ) {
        $this->addComponent('sidebar', new SidebarComponent());
        $this->addPageResources([
            new Stylesheet('components/common.css'),
            new Stylesheet('pages/change/page.css'),
            new Script('pages/change/page.js'),
        ]);
    }

    public function title(): string
    {
        return 'MAIA - change: ' . $this->changeId;
    }

    public function bodyClass(): string
    {
        return 'change-page';
    }

    public function sessionName(): string
    {
        return $this->sessionName;
    }

    public function workspaceName(): string
    {
        return $this->workspaceName;
    }

    public function changeId(): string
    {
        return $this->changeId;
    }

    public function render(): string
    {
        $page = $this;
        ob_start();
        require __DIR__ . '/template.php';
        return (string) ob_get_clean();
    }
}

$sessionName = trim((string) ($_SERVER['MAIA_URL_SESSION'] ?? ''));
$changeId = trim((string) ($_SERVER['MAIA_URL_CHANGE_ID'] ?? ''));
if ($sessionName === '' || !preg_match('/^[A-Za-z0-9_.%+\-]+$/', $sessionName) ||
    $changeId === '' || !preg_match('/^[A-Za-z0-9_.+\-]+$/', $changeId)) {
    http_response_code(404);
    header('Content-Type: text/plain; charset=utf-8');
    echo "Change not found.\n";
    exit;
}

$workspaceName = maia_session_workspace($sessionName) ?? '';
$page = new ChangePage($sessionName, $workspaceName, $changeId);
echo $page->render();
