<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */

declare(strict_types=1);

namespace Maia\Web\Components\Panels\Expandable;

use Maia\Web\Core\Component;
use Maia\Web\Core\Script;
use Maia\Web\Core\Stylesheet;

require_once dirname(__DIR__, 3) . '/core/component.php';

/** Wraps another component in the shared disclosure-panel markup. */
final class ExpandablePanel implements Component
{
    private string $id;
    private string $label;
    private Component $content;

    public function __construct(string $id, string $label, Component $content)
    {
        $this->id = $id;
        $this->label = $label;
        $this->content = $content;
    }

    /** @return list<\Maia\Web\Core\Resource> */
    public function resources(): array
    {
        return array_merge(
            [
                new Stylesheet('components/common.css'),
                new Stylesheet('components/panels/expandable/panel.css'),
                new Script('components/panels/expandable/panel.js'),
            ],
            $this->content->resources()
        );
    }

    public function render(): string
    {
        $safeId = htmlspecialchars($this->id, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        $safeLabel = htmlspecialchars($this->label, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        $content = $this->content->render();

        ob_start();
        require __DIR__ . '/template.php';
        return (string) ob_get_clean();
    }
}
