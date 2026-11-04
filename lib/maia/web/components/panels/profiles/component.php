<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */

declare(strict_types=1);

namespace Maia\Web\Components\Panels\Profiles;

use InvalidArgumentException;
use Maia\Web\Core\Component;
use Maia\Web\Core\Script;
use Maia\Web\Core\Stylesheet;

require_once dirname(__DIR__, 3) . '/core/component.php';

/** Lists and manages profiles in the current home or workspace scope. */
final class ProfilesPanel implements Component
{
    private string $scope;
    private string $scopeLabel;
    private string $workspaceName;

    public function __construct(string $scope, string $workspaceName = '')
    {
        if (!in_array($scope, ['home', 'workspace'], true)) {
            throw new InvalidArgumentException('Profiles can only be managed in home or workspace scope.');
        }
        if ($scope === 'workspace' && trim($workspaceName) === '') {
            throw new InvalidArgumentException('A workspace name is required for workspace-scoped profiles.');
        }

        $this->scope = $scope;
        $this->workspaceName = $scope === 'workspace' ? trim($workspaceName) : '';
        $this->scopeLabel = $scope === 'workspace'
            ? 'Workspace: ' . $this->workspaceName
            : 'Home scope';
    }

    /** @return list<\Maia\Web\Core\Resource> */
    public function resources(): array
    {
        return [
            new Stylesheet('components/common.css'),
            new Stylesheet('components/panels/profiles/component.css'),
            new Script('core/api.js'),
            new Script('core/ui.js'),
            new Script('components/panels/profiles/component.js'),
        ];
    }

    public function render(): string
    {
        $scope = htmlspecialchars($this->scope, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        $workspaceName = htmlspecialchars($this->workspaceName, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        $scopeLabel = htmlspecialchars($this->scopeLabel, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        ob_start();
        require __DIR__ . '/template.php';
        return (string) ob_get_clean();
    }
}
