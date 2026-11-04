<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */

declare(strict_types=1);

namespace Maia\Web\Pages\Workspace;

use InvalidArgumentException;
use Maia\Web\Components\PathBrowser\PathBrowser;
use Maia\Web\Components\Panels\Expandable\ExpandablePanel;
use Maia\Web\Components\Panels\Files\KnownFilesPanel;
use Maia\Web\Components\Panels\Profiles\ProfilesPanel;
use Maia\Web\Components\Panels\Skills\SkillsPanel;
use Maia\Web\Components\Panels\Tools\ToolsPanel;
use Maia\Web\Components\Workspace\Settings\WorkspaceSettingsComponent;
use Maia\Web\Components\Sidebar\SidebarComponent;
use Maia\Web\Core\Page;
use Maia\Web\Core\Stylesheet;

require_once __DIR__ . '/../common.php';
require_once dirname(__DIR__, 2) . '/core/page.php';
require_once dirname(__DIR__, 2) . '/core/workspace_root.php';
require_once dirname(__DIR__, 2) . '/components/sidebar/component.php';
require_once dirname(__DIR__, 2) . '/components/panels/expandable/panel.php';
require_once dirname(__DIR__, 2) . '/components/panels/files/component.php';
require_once dirname(__DIR__, 2) . '/components/panels/profiles/component.php';
require_once dirname(__DIR__, 2) . '/components/panels/skills/panel.php';
require_once dirname(__DIR__, 2) . '/components/panels/tools/panel.php';
require_once dirname(__DIR__, 2) . '/components/workspace/settings/component.php';
require_once dirname(__DIR__, 2) . '/components/path-browser/component.php';

final class WorkspacePage extends Page
{
    private string $workspaceName;
    private string $relativePath;

    public function __construct(string $workspaceName, string $relativePath)
    {
        $this->workspaceName = $workspaceName;
        $this->relativePath = $relativePath;

        $this->addComponent('sidebar', new SidebarComponent());
        $this->addComponent(
            'profiles',
            new ExpandablePanel('workspace-profiles', 'Profiles', new ProfilesPanel('workspace', $workspaceName))
        );
        $this->addComponent('files', new ExpandablePanel('workspace-known-files', 'Files', new KnownFilesPanel()));
        $this->addComponent('skills', new ExpandablePanel('skills', 'Skills', new SkillsPanel()));
        $this->addComponent('tools', new ExpandablePanel('tools', 'Tools', new ToolsPanel()));
        $this->addComponent('settings', new ExpandablePanel('workspace-settings', 'Settings', new WorkspaceSettingsComponent()));
        $this->addComponent(
            'browser',
            new PathBrowser(
                \Maia\Web\Core\WorkspaceRoot::resolve($workspaceName),
                $workspaceName,
                $relativePath
            )
        );
        $this->addPageResources([
            new Stylesheet('pages/workspace/page.css'),
        ]);
    }

    public function title(): string
    {
        return 'MAIA - workspace: ' . $this->workspaceName;
    }

    public function bodyClass(): string
    {
        return 'workspace-page';
    }

    public function workspaceName(): string
    {
        return $this->workspaceName;
    }

    public function relativePath(): string
    {
        return $this->relativePath;
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
$relativePath = trim(str_replace('\\', '/', (string) ($_SERVER['MAIA_URL_WORKSPACE_PATH'] ?? '')), '/');

try {
    $page = new WorkspacePage($workspaceName, $relativePath);
    echo $page->render();
} catch (InvalidArgumentException $error) {
    http_response_code(404);
    header('Content-Type: text/plain; charset=utf-8');
    echo "Workspace not found.\n";
}
