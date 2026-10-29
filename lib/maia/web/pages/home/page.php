<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */

declare(strict_types=1);

namespace Maia\Web\Pages\Home;

use Maia\Web\Components\Panels\Credentials\CredentialsPanel;
use Maia\Web\Components\Panels\Expandable\ExpandablePanel;
use Maia\Web\Components\Panels\Skills\SkillsPanel;
use Maia\Web\Components\Panels\Tools\ToolsPanel;
use Maia\Web\Components\Sidebar\SidebarComponent;
use Maia\Web\Core\Page;
use Maia\Web\Core\Stylesheet;

require_once __DIR__ . '/../common.php';
require_once dirname(__DIR__, 2) . '/core/page.php';
require_once dirname(__DIR__, 2) . '/components/sidebar/component.php';
require_once dirname(__DIR__, 2) . '/components/panels/expandable/panel.php';
require_once dirname(__DIR__, 2) . '/components/panels/credentials/panel.php';
require_once dirname(__DIR__, 2) . '/components/panels/skills/panel.php';
require_once dirname(__DIR__, 2) . '/components/panels/tools/panel.php';

final class HomePage extends Page
{
    public function __construct()
    {
        $this->addComponent('sidebar', new SidebarComponent());
        $this->addComponent(
            'credentials',
            new ExpandablePanel('credentials', 'Credentials', new CredentialsPanel())
        );
        $this->addComponent(
            'skills',
            new ExpandablePanel('skills', 'Skills', new SkillsPanel())
        );
        $this->addComponent(
            'tools',
            new ExpandablePanel('tools', 'Tools', new ToolsPanel())
        );

        $this->addPageResources([
            new Stylesheet('pages/home/page.css'),
        ]);
    }

    public function title(): string
    {
        return 'MAIA - home';
    }

    public function bodyClass(): string
    {
        return 'home-page';
    }

    public function render(): string
    {
        $page = $this;
        ob_start();
        require __DIR__ . '/template.php';
        return (string) ob_get_clean();
    }
}

$page = new HomePage();
echo $page->render();
