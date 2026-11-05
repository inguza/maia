<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 * Licensed under the GNU General Public License v3.0.
 */

declare(strict_types=1);

namespace Maia\Web\Components\Panels\Changes;

use Maia\Web\Core\Component;
use Maia\Web\Core\Script;
use Maia\Web\Core\Stylesheet;

require_once dirname(__DIR__, 3) . '/core/component.php';

final class ChangesPanel implements Component
{
    /** @return list<\Maia\Web\Core\Resource> */
    public function resources(): array
    {
        return [
            new Stylesheet('components/common.css'),
            new Stylesheet('components/panels/changes/panel.css'),
            new Script('core/api.js'),
            new Script('core/ui.js'),
            new Script('components/panels/changes/panel.js'),
        ];
    }

    public function render(): string
    {
        ob_start();
        require __DIR__ . '/template.php';
        return (string) ob_get_clean();
    }
}
