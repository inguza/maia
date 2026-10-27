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

function session_rename_error(int $status, string $message): never
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
    session_rename_error(405, 'Method not allowed.');
}

$input = json_decode((string) (file_get_contents('php://input') ?: ''), true);
if (!is_array($input)) {
    session_rename_error(400, 'Invalid session rename data.');
}

$oldName = trim((string) ($input['oldName'] ?? ''));
$newName = trim((string) ($input['newName'] ?? ''));
$namePattern = '/^[A-Za-z0-9_.%+-]+$/';
if ($oldName === '' || !preg_match($namePattern, $oldName)) {
    session_rename_error(400, 'Invalid current session name.');
}
if ($newName === '' || !preg_match($namePattern, $newName)) {
    session_rename_error(400, 'Invalid new session name.');
}
if ($oldName === $newName) {
    session_rename_error(400, 'The new and old session names must differ.');
}

$process = proc_open(
    [maia_web_binary(), 'session', 'rename', $newName, $oldName],
    [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
    $pipes,
    null,
    maia_web_environment()
);
if (!is_resource($process)) {
    session_rename_error(500, 'Unable to start MAIA.');
}

fclose($pipes[0]);
$output = (string) stream_get_contents($pipes[1]);
fclose($pipes[1]);
$error = (string) stream_get_contents($pipes[2]);
fclose($pipes[2]);
$status = proc_close($process);

if ($status !== 0) {
    session_rename_error(502, trim($error) ?: trim($output) ?: 'Unable to rename the session.');
}

echo json_encode([
    'ok' => true,
    'oldName' => $oldName,
    'newName' => $newName,
    'message' => trim($output) ?: 'Session renamed.',
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
