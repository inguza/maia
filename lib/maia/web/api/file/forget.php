<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */

declare(strict_types=1);

require_once __DIR__ . '/../web.php';

header('Content-Type: application/json; charset=utf-8');

function files_remove_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode([
        'ok' => false,
        'error' => $message,
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? 'POST') !== 'POST') {
    header('Allow: POST');
    files_remove_error(405, 'Method not allowed.');
}

$entry = trim((string) (file_get_contents('php://input') ?: ''));
if ($entry === '') {
    files_remove_error(400, 'A known file entry is required.');
}
if (strpos($entry, "\0") !== false || str_contains($entry, "\n") || str_contains($entry, "\r")) {
    files_remove_error(400, 'The known file entry contains an invalid character.');
}

// The CLI resolves the filename portion of filtered entries (for example,
// file.txt:1-100) relative to its current working directory. Run from the
// workspace root so relative entries resolve the same way in the GUI as in
// the workspace command-line workflow.
$workspaceRoot = maia_history_workspace_root();
$process = proc_open(
    [maia_binary(), 'file', 'forget', $entry],
    [
        0 => ['pipe', 'r'],
        1 => ['pipe', 'w'],
        2 => ['pipe', 'w'],
    ],
    $pipes,
    $workspaceRoot ?: null,
    maia_environment()
);

if (!is_resource($process)) {
    files_remove_error(500, 'Unable to start MAIA.');
}

fclose($pipes[0]);
$output = (string) stream_get_contents($pipes[1]);
fclose($pipes[1]);
$error = (string) stream_get_contents($pipes[2]);
fclose($pipes[2]);
$status = proc_close($process);

if ($status !== 0) {
    files_remove_error(502, trim($error) ?: trim($output) ?: 'Unable to forget the file.');
}

echo json_encode([
    'ok' => true,
    'path' => $entry,
    'message' => trim($output) ?: 'File forgotten.',
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
