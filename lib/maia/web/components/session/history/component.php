<?php
declare(strict_types=1);

namespace Maia\Web\Components\Session\History;

use Maia\Web\Core\Component;
use Maia\Web\Core\Script;
use Maia\Web\Core\Stylesheet;

require_once dirname(__DIR__, 3) . '/core/component.php';

final class SessionHistoryComponent implements Component
{
    /** @return list<\Maia\Web\Core\Resource> */
    public function resources(): array
    {
        return [
            new Stylesheet('components/common.css'),
            new Stylesheet('components/action-menu/component.css'),
            new Stylesheet('components/session/history/component.css'),
            new Script('core/api.js'),
            new Script('core/ui.js'),
            new Script('components/action-menu/component.js'),
            new Script('components/session/history/component.js'),
        ];
    }

    public function render(): string
    {
        ob_start();
        require __DIR__ . '/template.php';
        return (string) ob_get_clean();
    }
}
