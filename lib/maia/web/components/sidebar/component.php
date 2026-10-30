<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */

declare(strict_types=1);

namespace Maia\Web\Components\Sidebar;

use Maia\Web\Core\Component;
use Maia\Web\Core\Script;
use Maia\Web\Core\Stylesheet;

require_once dirname(__DIR__, 2) . '/core/component.php';

final class SidebarComponent implements Component
{
    /** @return list<\Maia\Web\Core\Resource> */
    public function resources(): array
    {
        return [
            new Stylesheet('components/common.css'),
            new Stylesheet('components/sidebar/component.css'),
            new Script('core/api.js'),
            new Script('core/ui.js'),
            new Script('components/sidebar/component.js'),
        ];
    }

    public function render(): string
    {
        $homeUrl = \maia_escape_html(\maia_base_path() . '/home');
        ob_start();
        require __DIR__ . '/template.php';
        return (string) ob_get_clean();
    }
}
