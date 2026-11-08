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
    private ?Component $changesPanel;
    private Component $skillsPanel;
    private Component $toolsPanel;
    private ?Component $approvalsPanel;
    private Component $behaviorPanel;
    private Component $configurationPanel;

    public function __construct(
        Component $composer,
        ?Component $filesPanel,
        Component $skillsPanel,
        Component $toolsPanel,
        Component $behaviorPanel,
        Component $configurationPanel,
        ?Component $workspacePanel = null,
        ?Component $changesPanel = null,
        ?Component $approvalsPanel = null
    ) {
        $this->composer = $composer;
        $this->filesPanel = $filesPanel;
        $this->workspacePanel = $workspacePanel;
        $this->changesPanel = $changesPanel;
        $this->skillsPanel = $skillsPanel;
        $this->toolsPanel = $toolsPanel;
        $this->approvalsPanel = $approvalsPanel;
        $this->behaviorPanel = $behaviorPanel;
        $this->configurationPanel = $configurationPanel;
    }

    /** @return list<\Maia\Web\Core\Resource> */
    public function resources(): array
    {
        $resources = $this->composer->resources();
        foreach ([$this->filesPanel, $this->changesPanel, $this->workspacePanel, $this->skillsPanel, $this->toolsPanel, $this->approvalsPanel, $this->behaviorPanel, $this->configurationPanel] as $panel) {
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
        $changesPanel = $this->changesPanel?->render() ?? '';
        $skillsPanel = $this->skillsPanel->render();
        $toolsPanel = $this->toolsPanel->render();
        $approvalsPanel = $this->approvalsPanel?->render() ?? '';
        $behaviorPanel = $this->behaviorPanel->render();
        $configurationPanel = $this->configurationPanel->render();
        ob_start();
        require __DIR__ . '/session-controls-template.php';
        return (string) ob_get_clean();
    }
}
