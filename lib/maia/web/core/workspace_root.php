<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */

declare(strict_types=1);

namespace Maia\Web\Core;

use InvalidArgumentException;

require_once __DIR__ . '/browser_root.php';

/** Resolves a workspace name to a trusted root and an independent URI root. */
final class WorkspaceRoot
{
    public static function resolve(string $workspaceName): BrowserRoot
    {
        if (!preg_match('/^[A-Za-z0-9_.%+\-]+$/', $workspaceName)) {
            throw new InvalidArgumentException('Invalid workspace name.');
        }
        $maiaHome = maia_home_dir();
        if ($maiaHome === null || $maiaHome === '') {
            throw new InvalidArgumentException('MAIA_HOME is not configured.');
        }
        $manifest = $maiaHome . DIRECTORY_SEPARATOR . 'workspaces' . DIRECTORY_SEPARATOR
            . $workspaceName . DIRECTORY_SEPARATOR . 'workspace.myl';
        if (!is_file($manifest)) {
            throw new InvalidArgumentException('Workspace does not exist.');
        }

        $configuredPath = '';
        foreach (file($manifest, FILE_IGNORE_NEW_LINES) ?: [] as $line) {
            if (preg_match('/^path:\s*(.*)$/', $line, $match)) {
                $configuredPath = trim($match[1]);
                break;
            }
        }
        if ($configuredPath === '') {
            throw new InvalidArgumentException('Workspace has no filesystem path.');
        }
        $base = dirname($maiaHome);
        if ($configuredPath === '~') {
            $configuredPath = $base;
        } elseif (str_starts_with($configuredPath, '~/') || str_starts_with($configuredPath, '~' . DIRECTORY_SEPARATOR)) {
            $configuredPath = $base . DIRECTORY_SEPARATOR . ltrim(substr($configuredPath, 2), '/\\');
        } elseif ($configuredPath[0] !== '/' && !preg_match('/^[A-Za-z]:[\\\/]/', $configuredPath)) {
            $configuredPath = $base . DIRECTORY_SEPARATOR . $configuredPath;
        }
        $root = realpath($configuredPath);
        if ($root === false || !is_dir($root)) {
            throw new InvalidArgumentException('Workspace path is not an existing directory.');
        }
        return new BrowserRoot($root, '/workspace/' . rawurlencode($workspaceName));
    }
}
