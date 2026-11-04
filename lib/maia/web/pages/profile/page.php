<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */

declare(strict_types=1);

namespace Maia\Web\Pages\Profile;

use Maia\Web\Components\Panels\Expandable\ExpandablePanel;
use Maia\Web\Components\Panels\Skills\SkillsPanel;
use Maia\Web\Components\Panels\Tools\ToolsPanel;
use Maia\Web\Components\Profile\Settings\ProfileSettingsComponent;
use Maia\Web\Components\Sidebar\SidebarComponent;
use Maia\Web\Core\Page;
use Maia\Web\Core\Stylesheet;

require_once __DIR__ . '/../common.php';
require_once dirname(__DIR__, 2) . '/core/page.php';
require_once dirname(__DIR__, 2) . '/components/sidebar/component.php';
require_once dirname(__DIR__, 2) . '/components/profile/settings/component.php';
require_once dirname(__DIR__, 2) . '/components/panels/expandable/panel.php';
require_once dirname(__DIR__, 2) . '/components/panels/skills/panel.php';
require_once dirname(__DIR__, 2) . '/components/panels/tools/panel.php';

final class ProfilePage extends Page
{
    private string $profileName;
    private string $workspaceName;

    public function __construct(string $profileName, string $workspaceName = '')
    {
        $this->profileName = $profileName;
        $this->workspaceName = $workspaceName;
        $this->addComponent('sidebar', new SidebarComponent());
        $this->addComponent('profile-settings', new ProfileSettingsComponent());
        $this->addComponent(
            'skills',
            new ExpandablePanel('skills', 'Skills', new SkillsPanel())
        );
        $this->addComponent(
            'tools',
            new ExpandablePanel('tools', 'Tools', new ToolsPanel())
        );
        $this->addPageResources([
            new Stylesheet('pages/profile/page.css'),
        ]);
    }

    public function title(): string
    {
        return 'MAIA - profile: ' . $this->profileName;
    }

    public function bodyClass(): string
    {
        return 'profile-page';
    }

    public function profileName(): string
    {
        return $this->profileName;
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

$profileName = trim((string) ($_SERVER['MAIA_URL_PROFILE'] ?? ''));
if ($profileName === '' || !preg_match('/^[A-Za-z0-9_.%+\-]+$/', $profileName)) {
    http_response_code(404);
    echo "Profile not found.\n";
    return;
}

$workspaceName = trim((string) ($_SERVER['MAIA_URL_WORKSPACE'] ?? ''));
if ($workspaceName !== '' && !preg_match('/^[A-Za-z0-9_.%+\\-]+$/', $workspaceName)) {
    http_response_code(404);
    echo "Workspace not found.\\n";
    return;
}

$page = new ProfilePage($profileName, $workspaceName);
echo $page->render();
