<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */

declare(strict_types=1);

require_once __DIR__ . '/../web.php';

header('Content-Type: application/json; charset=utf-8');

function files_list_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode([
        'ok' => false,
        'error' => $message,
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
    header('Allow: GET');
    files_list_error(405, 'Method not allowed.');
}

$process = proc_open(
    [maia_web_binary(), 'file', 'list', '--raw'],
    [
        0 => ['pipe', 'r'],
        1 => ['pipe', 'w'],
        2 => ['pipe', 'w'],
    ],
    $pipes,
    null,
    maia_web_environment()
);

if (!is_resource($process)) {
    files_list_error(500, 'Unable to start MAIA.');
}

fclose($pipes[0]);
$output = (string) stream_get_contents($pipes[1]);
fclose($pipes[1]);
$error = (string) stream_get_contents($pipes[2]);
fclose($pipes[2]);
$status = proc_close($process);

if ($status !== 0) {
    $diagnostic = trim($error) ?: trim($output);
    // A new session may not have a workspace or filesets yet. That is an
    // empty known-file list, not an API failure.
    if (stripos($diagnostic, 'No filesets found') !== false ||
        stripos($diagnostic, 'No workspace defined') !== false ||
        stripos($diagnostic, 'no workspace') !== false) {
        echo json_encode([
            'ok' => true,
            'files' => [],
        ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
        exit;
    }
    files_list_error(502, $diagnostic ?: 'Unable to list known files.');
}

$files = [];
foreach (preg_split('/\R/', $output) as $line) {
    $line = trim($line);
    if ($line !== '') {
        $files[] = $line;
    }
}

$files = array_values(array_unique($files));

echo json_encode([
    'ok' => true,
    'files' => $files,
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
