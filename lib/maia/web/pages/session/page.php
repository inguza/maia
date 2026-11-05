<?php
declare(strict_types=1);

namespace Maia\Web\Pages\Session;

use Maia\Web\Components\Session\Composer\SessionComposerComponent;
use Maia\Web\Components\Session\Composer\SessionControlsComponent;
use Maia\Web\Components\Session\History\SessionHistoryComponent;
use Maia\Web\Components\Sidebar\SidebarComponent;
use Maia\Web\Components\PathBrowser\PathBrowser;
use Maia\Web\Core\BrowserRoot;
use Maia\Web\Core\WorkspaceRoot;
use Maia\Web\Components\Panels\Expandable\ExpandablePanel;
use Maia\Web\Components\Panels\Files\KnownFilesPanel;
use Maia\Web\Components\Panels\Changes\ChangesPanel;
use Maia\Web\Components\Panels\Skills\SkillsPanel;
use Maia\Web\Components\Panels\Tools\ToolsPanel;
use Maia\Web\Core\Page;
use Maia\Web\Core\Stylesheet;

require_once __DIR__ . '/../common.php';
require_once dirname(__DIR__, 2) . '/core/page.php';
require_once dirname(__DIR__, 2) . '/api/web.php';
require_once dirname(__DIR__, 2) . '/components/sidebar/component.php';
require_once dirname(__DIR__, 2) . '/components/panels/expandable/panel.php';
require_once dirname(__DIR__, 2) . '/components/panels/files/component.php';
require_once dirname(__DIR__, 2) . '/components/panels/changes/panel.php';
require_once dirname(__DIR__, 2) . '/components/panels/skills/panel.php';
require_once dirname(__DIR__, 2) . '/components/panels/tools/panel.php';
require_once dirname(__DIR__, 2) . '/components/session/history/component.php';
require_once dirname(__DIR__, 2) . '/components/session/composer/component.php';
require_once dirname(__DIR__, 2) . '/components/session/composer/session-controls.php';
require_once dirname(__DIR__, 2) . '/components/path-browser/component.php';
require_once dirname(__DIR__, 2) . '/core/workspace_root.php';

final class SessionPage extends Page
{
    private string $sessionName;
    private string $workspaceName;

    public function __construct(string $sessionName, string $workspaceName = '')
    {
        $this->sessionName = $sessionName;
        $this->workspaceName = $workspaceName;
        $this->addComponent('sidebar', new SidebarComponent());
        $this->addComponent('history', new SessionHistoryComponent());

        $filesPanel = $workspaceName !== ''
            ? new ExpandablePanel('files', 'Files', new KnownFilesPanel())
            : null;
        $changesPanel = $workspaceName !== ''
            ? new ExpandablePanel('changes', 'Changes', new ChangesPanel())
            : null;
        $workspacePanel = null;
        if ($workspaceName !== '') {
            $resolvedWorkspace = WorkspaceRoot::resolve($workspaceName);
            $sessionBrowserRoot = new BrowserRoot(
                $resolvedWorkspace->filesystemRoot(),
                '/session/' . rawurlencode($sessionName)
            );
            $workspacePanel = new ExpandablePanel(
                'session-workspace',
                'Workspace',
                new PathBrowser(
                    $sessionBrowserRoot,
                    $workspaceName,
                    '',
                    $sessionName,
                    '',
                    false,
                    '?workspace=1'
                )
            );
        }
        $skillsPanel = new ExpandablePanel('skills', 'Skills', new SkillsPanel());
        $toolsPanel = new ExpandablePanel('tools', 'Tools', new ToolsPanel());
        $composer = new SessionComposerComponent();
        $this->addComponent(
            'composer',
            new SessionControlsComponent($composer, $filesPanel, $skillsPanel, $toolsPanel, $workspacePanel, $changesPanel)
        );
        $this->addPageResources([new Stylesheet('pages/session/page.css')]);
    }

    public function title(): string
    {
        return 'MAIA - session: ' . $this->sessionName;
    }

    public function bodyClass(): string
    {
        return 'session-page';
    }

    public function sessionName(): string
    {
        return $this->sessionName;
    }

    public function workspaceName(): string
    {
        return $this->workspaceName;
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
if ($sessionName === '' || !preg_match('/^[A-Za-z0-9_.%+\-]+$/', $sessionName)) {
    http_response_code(404);
    header('Content-Type: text/plain; charset=utf-8');
    echo "Session not found.\n";
    exit;
}
$workspaceName = trim((string) (maia_session_workspace($sessionName) ?? ''));
$page = new SessionPage($sessionName, $workspaceName);
echo $page->render();
