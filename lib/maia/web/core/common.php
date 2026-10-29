<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */

function maia_base_path(): string
{
    $script = parse_url((string) ($_SERVER['SCRIPT_NAME'] ?? ''), PHP_URL_PATH);
    if (!is_string($script) || $script === '') {
        return '';
    }
    $base = str_replace('\\', '/', dirname($script));
    return $base === '.' || $base === '/' ? '' : rtrim($base, '/');
}

function maia_request_path(): string
{
    $path = parse_url((string) ($_SERVER['REQUEST_URI'] ?? '/'), PHP_URL_PATH);
    $path = is_string($path) && $path !== '' ? $path : '/';
    $base = maia_base_path();
    if ($base !== '' && ($path === $base || str_starts_with($path, $base . '/'))) {
        $path = substr($path, strlen($base));
    }
    return $path === '' ? '/' : $path;
}

function maia_home_dir(): ?string
{
    $home = getenv('MAIA_HOME')."/.maia";
    return is_string($home) && $home !== '' ? $home : null;
}

function maia_binary(): string
{
    return getenv('MAIA_BIN') ?: 'maia';
}

function maia_escape_html(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}
