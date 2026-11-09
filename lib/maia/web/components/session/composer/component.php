<?php
declare(strict_types=1);

namespace Maia\Web\Components\Session\Composer;

use Maia\Web\Core\Component;
use Maia\Web\Core\Script;
use Maia\Web\Core\Stylesheet;

require_once dirname(__DIR__, 3) . '/core/component.php';

final class SessionComposerComponent implements Component
{
    /** @return list<\Maia\Web\Core\Resource> */
    public function resources(): array
    {
        $composerVersion = @filemtime(__DIR__ . '/component.js') ?: 1;
        return [
            new Stylesheet('components/common.css'),
            new Stylesheet('components/session/composer/component.css'),
            new Script('core/api.js'),
            new Script('core/ui.js'),
            new Script('components/session/composer/component.js?v=' . $composerVersion),
        ];
    }

    public function render(): string
    {
        ob_start();
        require __DIR__ . '/template.php';
        return (string) ob_get_clean();
    }
}
