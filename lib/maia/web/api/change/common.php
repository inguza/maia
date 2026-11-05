<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 * Licensed under the GNU General Public License v3.0.
 */

declare(strict_types=1);

require_once dirname(__DIR__) . '/web.php';

function change_api_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

/** @return array{output: string, error: string, status: int} */
function change_api_run(array $arguments): array
{
    $process = proc_open(
        array_merge([maia_binary()], $arguments),
        [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
        $pipes,
        null,
        maia_environment()
    );
    if (!is_resource($process)) {
        return ['output' => '', 'error' => 'Unable to start MAIA.', 'status' => 1];
    }

    fclose($pipes[0]);
    $streams = [1 => $pipes[1], 2 => $pipes[2]];
    foreach ($streams as $stream) {
        stream_set_blocking($stream, false);
    }
    $output = '';
    $error = '';
    while ($streams !== []) {
        $read = array_values($streams);
        $write = null;
        $except = null;
        $readyCount = @stream_select($read, $write, $except, 1);
        if ($readyCount === false) {
            continue;
        }
        foreach ($read as $readyStream) {
            $key = array_search($readyStream, $streams, true);
            if ($key === false) {
                continue;
            }
            $chunk = fread($readyStream, 8192);
            if ($chunk !== false && $chunk !== '') {
                if ($key === 1) {
                    $output .= $chunk;
                } else {
                    $error .= $chunk;
                }
            }
            if (feof($readyStream)) {
                fclose($readyStream);
                unset($streams[$key]);
            }
        }
    }
    return ['output' => $output, 'error' => $error, 'status' => proc_close($process)];
}

function change_api_file_url(string $filename): ?string
{
    static $cachedSession = null;
    static $cachedWorkspaceRoot = null;

    $session = maia_selected_session();
    if ($session === null) {
        return null;
    }
    if ($cachedSession !== $session) {
        $cachedSession = $session;
        $cachedWorkspaceRoot = maia_history_workspace_root();
    }
    $workspaceRoot = $cachedWorkspaceRoot;
    $isWindowsAbsolute = strlen($filename) >= 3 && ctype_alpha($filename[0]) &&
        $filename[1] === ':' && in_array($filename[2], ['/', chr(92)], true);
    if ($workspaceRoot === null || $filename === '' || str_contains($filename, "\0") ||
        str_starts_with($filename, '/') || $isWindowsAbsolute) {
        return null;
    }

    $parts = explode('/', str_replace(chr(92), '/', $filename));
    if (in_array('..', $parts, true)) {
        return null;
    }
    $candidate = realpath($workspaceRoot . DIRECTORY_SEPARATOR . implode(DIRECTORY_SEPARATOR, $parts));
    if ($candidate === false || !is_file($candidate)) {
        return null;
    }
    $prefix = rtrim($workspaceRoot, DIRECTORY_SEPARATOR . '/' . chr(92)) . DIRECTORY_SEPARATOR;
    if (!str_starts_with($candidate, $prefix)) {
        return null;
    }

    $relative = str_replace(chr(92), '/', substr($candidate, strlen($prefix)));
    $encoded = implode('/', array_map('rawurlencode', explode('/', $relative)));
    return maia_base_path() . '/session/' . rawurlencode($session) . '/' . $encoded;
}

/** @return list<array{id: string, type: string, state: string, filename: string, fileUrl: ?string}> */
function change_api_parse_list(string $output): array
{
    $changes = [];
    foreach (preg_split('/\R/', $output) as $line) {
        if (!preg_match('/^\s*(\S+)\s+(\S+)\s+(\S+)(?:\s+(.*))?$/', $line, $match)) {
            continue;
        }
        [, $id, $type, $state] = $match;
        if (!preg_match('/^[A-Za-z0-9_.+\-]+$/', $id) ||
            !in_array($state, ['pending', 'applied', 'skipped', 'running', 'finished', 'failed'], true)) {
            continue;
        }
        $filename = trim((string) ($match[4] ?? ''));
        $changes[] = [
            'id' => $id,
            'type' => $type,
            'state' => $state,
            'filename' => $filename,
            'fileUrl' => change_api_file_url($filename),
        ];
    }
    return $changes;
}

/** @return array{id: string, type: string, state: string, filename: string, fileUrl: ?string}|null */
function change_api_parse_show_metadata(string $id, string $output): ?array
{
    $state = '';
    $type = '';
    $filename = '';
    foreach (preg_split('/\R/', $output) as $line) {
        if (str_starts_with($line, 'Sub-change:')) {
            break;
        }
        if ($state === '' && preg_match('/^State:\s*(pending|applied|skipped|running|finished|failed)\s*$/i', $line, $match)) {
            $state = strtolower($match[1]);
        }
        if ($type === '' && preg_match('/^Type:\s*(\S+)\s*$/i', $line, $match)) {
            $type = strtolower($match[1]);
        }
        if ($filename === '' && preg_match('/^Filename:\s*(.*)$/i', $line, $match)) {
            $filename = trim($match[1]);
        }
    }

    if (!preg_match('/-[0-9]{1,3}$/', $id)) {
        $type = 'set';
        $filename = '';
    }
    if ($state === '') {
        return null;
    }

    return [
        'id' => $id,
        'type' => $type !== '' ? $type : 'unknown',
        'state' => $state,
        'filename' => $filename,
        'fileUrl' => change_api_file_url($filename),
    ];
}
