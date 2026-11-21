<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */

declare(strict_types=1);

namespace Maia\Web\Components\PathBrowser;

use Maia\Web\Core\BrowserRoot;
use Maia\Web\Core\Component;
use Maia\Web\Core\Script;
use Maia\Web\Core\Stylesheet;

require_once dirname(__DIR__, 2) . '/core/component.php';
require_once dirname(__DIR__, 2) . '/core/browser_root.php';

/** Generic UI browser. The API enforces the same filesystem boundary server-side. */
final class PathBrowser implements Component
{
    private BrowserRoot $root;
    private string $workspaceName;
    private string $relativePath;
    private string $sessionTarget;
    private string $initialFile;
    private bool $fileOnly;
    private string $rootQuery;
    private string $heading;
    private bool $collapsibleHeading;

    public function __construct(
        BrowserRoot $root,
        string $workspaceName,
        string $relativePath = '',
        string $sessionTarget = '',
        string $initialFile = '',
        bool $fileOnly = false,
        string $rootQuery = '',
        string $heading = '',
        bool $collapsibleHeading = false
    ) {
        $this->root = $root;
        $this->workspaceName = $workspaceName;
        $this->relativePath = $relativePath;
        $this->sessionTarget = $sessionTarget;
        $this->initialFile = $initialFile;
        $this->fileOnly = $fileOnly;
        $this->rootQuery = $rootQuery;
        $this->heading = $heading;
        $this->collapsibleHeading = $collapsibleHeading;
    }

    /** @return list<\Maia\Web\Core\Resource> */
    public function resources(): array
    {
        return [
            new Stylesheet('components/common.css'),
            new Stylesheet('components/path-browser/component.css'),
            new Stylesheet('components/action-menu/component.css'),
            new Script('core/api.js'),
            new Script('core/ui.js'),
            new Script('components/action-menu/component.js'),
            new Script('components/path-browser/marked-18.0.14.umd.js'),
            new Script('components/path-browser/purify-3.4.17.min.js'),
            new Script('components/path-browser/markdown-viewer.js'),
            new Script('components/path-browser/component.js'),
        ];
    }

    public function render(): string
    {
        $workspaceName = htmlspecialchars($this->workspaceName, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        $relativePath = htmlspecialchars($this->relativePath, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        $uriRoot = htmlspecialchars($this->root->uriRoot(), ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        $sessionTarget = htmlspecialchars($this->sessionTarget, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        $initialFile = htmlspecialchars($this->initialFile, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        $fileOnly = $this->fileOnly ? '1' : '0';
        $rootQuery = htmlspecialchars($this->rootQuery, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        $heading = htmlspecialchars($this->heading, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        $collapsibleHeading = $this->collapsibleHeading;
        $initialEntries = $this->directoryEntries();
        $initialLoaded = $initialEntries === null ? '0' : '1';
        $initialEntriesJson = htmlspecialchars(
            json_encode($initialEntries ?? [], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE),
            ENT_QUOTES | ENT_SUBSTITUTE,
            'UTF-8'
        );
        $initialEntries = $initialEntries ?? [];
        ob_start();
        require __DIR__ . '/template.php';
        return (string) ob_get_clean();
    }

    /** @return list<array{name:string,path:string,type:string,size:int|null,empty:bool}>|null */
    private function directoryEntries(): ?array
    {
        $directory = $this->root->resolve($this->relativePath);
        if ($directory === null || !is_dir($directory)) {
            return null;
        }

        $filesystemRoot = $this->root->filesystemRoot();
        $rootPrefix = rtrim($filesystemRoot, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR;
        $relativePath = trim(str_replace('\\', '/', $this->relativePath), '/');
        $relativePath = implode('/', array_values(array_filter(
            explode('/', $relativePath),
            static fn(string $part): bool => $part !== '' && $part !== '.'
        )));
        $entries = [];
        foreach (scandir($directory) ?: [] as $name) {
            if ($name === '.' || $name === '..') {
                continue;
            }
            $fullPath = $directory . DIRECTORY_SEPARATOR . $name;
            $resolved = realpath($fullPath);
            if ($resolved === false || ($resolved !== $filesystemRoot && !str_starts_with($resolved, $rootPrefix))) {
                continue;
            }
            $isDirectory = is_dir($fullPath);
            $children = $isDirectory ? @scandir($fullPath) : false;
            $entries[] = [
                'name' => $name,
                'path' => ($relativePath === '' ? '' : $relativePath . '/') . $name,
                'type' => $isDirectory ? 'directory' : 'file',
                'size' => $isDirectory ? null : (is_file($fullPath) ? (@filesize($fullPath) ?: 0) : null),
                'empty' => $isDirectory && $children !== false && count(array_diff($children, ['.', '..'])) === 0,
            ];
        }
        usort($entries, static function (array $a, array $b): int {
            return [$a['type'] !== 'directory', strtolower($a['name'])] <=> [$b['type'] !== 'directory', strtolower($b['name'])];
        });
        return $entries;
    }
}
