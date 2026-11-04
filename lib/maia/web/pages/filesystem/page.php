<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */

declare(strict_types=1);

namespace Maia\Web\Pages\Filesystem;

use InvalidArgumentException;
use Maia\Web\Components\PathBrowser\PathBrowser;
use Maia\Web\Components\Sidebar\SidebarComponent;
use Maia\Web\Core\BrowserRoot;
use Maia\Web\Core\Page;
use Maia\Web\Core\Stylesheet;

require_once __DIR__ . '/../common.php';
require_once dirname(__DIR__, 2) . '/core/page.php';
require_once dirname(__DIR__, 2) . '/core/browser_root.php';
require_once dirname(__DIR__, 2) . '/core/workspace_root.php';
require_once dirname(__DIR__, 2) . '/components/sidebar/component.php';
require_once dirname(__DIR__, 2) . '/components/path-browser/component.php';

final class FilesystemPage extends Page
{
    private string $workspaceName;
    private string $sessionName;
    private string $relativePath;
    private bool $fileOnly;

    public function __construct(
        string $workspaceName,
        string $sessionName,
        BrowserRoot $root,
        string $relativePath
    ) {
        $relativePath = trim(str_replace('\\', '/', $relativePath), '/');
        $relativePath = implode('/', array_values(array_filter(
            explode('/', $relativePath),
            static fn(string $part): bool => $part !== '' && $part !== '.'
        )));
        $resolvedPath = $root->resolve($relativePath);
        if ($resolvedPath === null || (!is_dir($resolvedPath) && !is_file($resolvedPath))) {
            throw new InvalidArgumentException('Filesystem path not found.');
        }

        $this->workspaceName = $workspaceName;
        $this->sessionName = $sessionName;
        $this->relativePath = $relativePath;
        $this->fileOnly = is_file($resolvedPath);

        $browserPath = $relativePath;
        $initialFile = '';
        if ($this->fileOnly) {
            $initialFile = $relativePath;
            $parent = dirname($relativePath);
            $browserPath = $parent === '.' ? '' : $parent;
        }

        $this->addComponent('sidebar', new SidebarComponent());
        $this->addComponent(
            'browser',
            new PathBrowser($root, $workspaceName, $browserPath, $sessionName, $initialFile, $initialFile !== '')
        );
        $this->addPageResources([new Stylesheet('pages/filesystem/page.css')]);
    }

    public function title(): string
    {
        $context = $this->sessionName !== ''
            ? 'session ' . $this->sessionName
            : 'workspace ' . $this->workspaceName;
        $path = $this->relativePath === '' ? '/' : '/' . $this->relativePath;
        return 'MAIA - Filesystem — ' . $context . ' — ' . $path;
    }

    public function bodyClass(): string
    {
        return 'filesystem-page';
    }

    public function workspaceName(): string
    {
        return $this->workspaceName;
    }

    public function sessionName(): string
    {
        return $this->sessionName;
    }

    public function fileOnly(): bool
    {
        return $this->fileOnly;
    }

    public function render(): string
    {
        $page = $this;
        ob_start();
        require __DIR__ . '/template.php';
        return (string) ob_get_clean();
    }
}

$workspaceName = trim((string) ($_SERVER['MAIA_URL_WORKSPACE'] ?? ''));
$sessionName = trim((string) ($_SERVER['MAIA_URL_SESSION'] ?? ''));
$relativePath = (string) ($_SERVER['MAIA_URL_WORKSPACE_PATH'] ?? '');

try {
    $workspaceRoot = \Maia\Web\Core\WorkspaceRoot::resolve($workspaceName);
    $browserRoot = $sessionName === ''
        ? $workspaceRoot
        : new BrowserRoot($workspaceRoot->filesystemRoot(), '/session/' . rawurlencode($sessionName));
    $page = new FilesystemPage($workspaceName, $sessionName, $browserRoot, $relativePath);
    echo $page->render();
} catch (InvalidArgumentException $error) {
    http_response_code(404);
    header('Content-Type: text/plain; charset=utf-8');
    echo "Filesystem path not found.\n";
}
