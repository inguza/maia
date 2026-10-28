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

function workspace_delete_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? 'POST') !== 'POST') {
    header('Allow: POST');
    workspace_delete_error(405, 'Method not allowed.');
}

$name = trim((string) (file_get_contents('php://input') ?: ''));
if ($name === '' || !preg_match('/^[A-Za-z0-9][A-Za-z0-9_-]*$/', $name)) {
    workspace_delete_error(400, 'Invalid workspace name.');
}

$process = proc_open(
    [maia_web_binary(), 'workspace', 'delete', $name],
    [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
    $pipes,
    null,
    maia_web_environment()
);
if (!is_resource($process)) {
    workspace_delete_error(500, 'Unable to start MAIA.');
}
fclose($pipes[0]);
$output = (string) stream_get_contents($pipes[1]);
fclose($pipes[1]);
$error = (string) stream_get_contents($pipes[2]);
fclose($pipes[2]);
$status = proc_close($process);
if ($status !== 0) {
    workspace_delete_error(502, trim($error) ?: trim($output) ?: 'Unable to delete the workspace.');
}

echo json_encode(['ok' => true, 'name' => $name, 'message' => trim($output) ?: 'Workspace deleted.'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
