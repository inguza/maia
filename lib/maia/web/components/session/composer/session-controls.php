<?php
declare(strict_types=1);

namespace Maia\Web\Components\Session\Composer;

use Maia\Web\Core\Component;

require_once dirname(__DIR__, 3) . '/core/component.php';

/** Composes the message form with its session-specific disclosure panels. */
final class SessionControlsComponent implements Component
{
    private Component $composer;
    private ?Component $filesPanel;
    private ?Component $workspacePanel;
    private Component $skillsPanel;
    private Component $toolsPanel;

    public function __construct(
        Component $composer,
        ?Component $filesPanel,
        Component $skillsPanel,
        Component $toolsPanel,
        ?Component $workspacePanel = null
    ) {
        $this->composer = $composer;
        $this->filesPanel = $filesPanel;
        $this->workspacePanel = $workspacePanel;
        $this->skillsPanel = $skillsPanel;
        $this->toolsPanel = $toolsPanel;
    }

    /** @return list<\Maia\Web\Core\Resource> */
    public function resources(): array
    {
        $resources = $this->composer->resources();
        foreach ([$this->filesPanel, $this->workspacePanel, $this->skillsPanel, $this->toolsPanel] as $panel) {
            if ($panel !== null) {
                $resources = array_merge($resources, $panel->resources());
            }
        }
        return $resources;
    }

    public function render(): string
    {
        $composer = $this->composer->render();
        $filesPanel = $this->filesPanel?->render() ?? '';
        $workspacePanel = $this->workspacePanel?->render() ?? '';
        $skillsPanel = $this->skillsPanel->render();
        $toolsPanel = $this->toolsPanel->render();
        ob_start();
        require __DIR__ . '/session-controls-template.php';
        return (string) ob_get_clean();
    }
}
