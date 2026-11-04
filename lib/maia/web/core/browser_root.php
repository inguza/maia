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

require_once __DIR__ . '/common.php';

use InvalidArgumentException;

/** A trusted filesystem boundary paired with its public URL root. */
final class BrowserRoot
{
    private string $filesystemRoot;
    private string $uriRoot;

    public function __construct(string $filesystemRoot, string $uriRoot)
    {
        $resolved = realpath($filesystemRoot);
        if ($resolved === false || !is_dir($resolved)) {
            throw new InvalidArgumentException('The browser filesystem root must be an existing directory.');
        }
        $uriRoot = '/' . trim(str_replace('\\', '/', $uriRoot), '/');
        if ($uriRoot === '/') {
            throw new InvalidArgumentException('The browser URI root must not be empty.');
        }
        $this->filesystemRoot = rtrim($resolved, DIRECTORY_SEPARATOR . '/\\');
        $this->uriRoot = $uriRoot;
    }

    public function filesystemRoot(): string
    {
        return $this->filesystemRoot;
    }

    public function uriRoot(): string
    {
        return $this->uriRoot;
    }

    /** Resolve a relative path only if its canonical target remains below the trusted root. */
    public function resolve(string $relativePath): ?string
    {
        $relativePath = $this->normalizeRelativePath($relativePath);
        if ($relativePath === null) {
            return null;
        }
        $candidate = $relativePath === ''
            ? $this->filesystemRoot
            : $this->filesystemRoot . DIRECTORY_SEPARATOR . str_replace('/', DIRECTORY_SEPARATOR, $relativePath);
        $resolved = realpath($candidate);
        if ($resolved === false) {
            return null;
        }
        $prefix = $this->filesystemRoot . DIRECTORY_SEPARATOR;
        if ($resolved !== $this->filesystemRoot && !str_starts_with($resolved, $prefix)) {
            return null;
        }
        return $resolved;
    }

    /** Build a URL below the URI root; never expose or derive it from the filesystem path. */
    public function urlFor(string $relativePath = ''): ?string
    {
        $relativePath = $this->normalizeRelativePath($relativePath);
        if ($relativePath === null) {
            return null;
        }
        $suffix = $relativePath === ''
            ? ''
            : '/' . implode('/', array_map('rawurlencode', explode('/', $relativePath)));
        return maia_base_path() . $this->uriRoot . $suffix;
    }

    private function normalizeRelativePath(string $path): ?string
    {
        if (str_contains($path, "\0")) {
            return null;
        }
        $path = str_replace('\\', '/', trim($path));
        if (str_starts_with($path, '/') || preg_match('/^[A-Za-z]:\//', $path)) {
            return null;
        }
        $parts = [];
        foreach (explode('/', $path) as $part) {
            if ($part === '' || $part === '.') {
                continue;
            }
            if ($part === '..') {
                return null;
            }
            $parts[] = $part;
        }
        return implode('/', $parts);
    }
}
