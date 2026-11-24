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
    $home = getenv('MAIA_HOME');
    return is_string($home) && $home !== '' ? $home . DIRECTORY_SEPARATOR . '.maia' : null;
}

function maia_binary(): string
{
    return getenv('MAIA_BIN') ?: 'maia';
}

/**
 * Parse MYL text into key/value entries, including two-space-indented
 * multiline values. Values remain strings, matching the Bash MYL helpers.
 *
 * @return array<string, string>
 */
function myl_parse(string $text): array
{
    $values = [];
    $current = null;
    $firstContinuation = true;

    foreach (explode("\n", $text) as $line) {
        $line = rtrim($line, "\r");
        if (str_starts_with($line, '  ') && $current !== null) {
            $value = substr($line, 2);
            if ($firstContinuation) {
                $values[$current] = $value;
                $firstContinuation = false;
            } else {
                $values[$current] .= "\n" . $value;
            }
            continue;
        }

        $current = null;
        $firstContinuation = true;
        if (preg_match('/^([^:\\s]+):[ \\t]?(.*)$/', $line, $match)) {
            $current = $match[1];
            $values[$current] = $match[2];
        }
    }

    return $values;
}

/** Load a MYL file into an associative array, replacing keys found in it. */
function myl_load(string $file, array &$values): bool
{
    if ($file === '' || !is_file($file) || !is_readable($file)) {
        return false;
    }
    $text = @file_get_contents($file);
    if ($text === false) {
        return false;
    }
    foreach (myl_parse($text) as $key => $value) {
        $values[$key] = $value;
    }
    return true;
}

/** Read one key from a MYL file; null means the key is absent or unreadable. */
function myl_get(string $file, string $field): ?string
{
    $values = [];
    if (!myl_load($file, $values) || !array_key_exists($field, $values)) {
        return null;
    }
    return $values[$field];
}

/** Return the merged web policy for this request; later files take precedence. */
function maia_policy(): array
{
    static $policy = null;
    if ($policy !== null) {
        return $policy;
    }

    $binary = realpath(maia_binary());
    $libconfig = $binary === false
        ? null
        : dirname(dirname($binary)) . DIRECTORY_SEPARATOR . 'lib' . DIRECTORY_SEPARATOR
            . 'maia' . DIRECTORY_SEPARATOR . 'config' . DIRECTORY_SEPARATOR . 'policy.myl';
    $home = maia_home_dir();
    $sources = [
        $home === null ? null : $home . DIRECTORY_SEPARATOR . 'policy.myl',
        '/etc/maia/policy.myl',
        $libconfig,
    ];

    $policy = [];
    foreach ($sources as $path) {
        if ($path !== null) {
            myl_load($path, $policy);
        }
    }
    return $policy;
}

function maia_policy_get(string $key, ?string $default = null): ?string
{
    $policy = maia_policy();
    return array_key_exists($key, $policy) ? $policy[$key] : $default;
}

function maia_policy_bool(string $key, bool $default = false): bool
{
    $value = maia_policy_get($key);
    if ($value === null) {
        return $default;
    }
    return in_array(strtolower(trim($value)), ['1', 'true', 'yes', 'on'], true);
}

function maia_escape_html(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}
