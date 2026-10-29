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

function history_action_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    header('Allow: POST');
    history_action_error(405, 'Method not allowed.');
}

$input = json_decode((string) (file_get_contents('php://input') ?: ''), true);
if (!is_array($input)) {
    history_action_error(400, 'Invalid history action.');
}

$action = (string) ($input['action'] ?? '');
$index = $input['index'] ?? null;
$role = (string) ($input['role'] ?? '');
$roleIndex = $input['roleIndex'] ?? null;
$arguments = ['history'];
$body = '';

if (in_array($action, ['hide', 'unhide', 'delete'], true)) {
    if (!is_int($index) && !(is_string($index) && ctype_digit($index))) {
        history_action_error(400, 'A history index is required.');
    }
    $arguments[] = $action;
    $arguments[] = (string) $index;
} elseif (in_array($action, ['prune', 'cut'], true)) {
    if (!in_array($role, ['user', 'assistant', 'tool', 'reasoning'], true) ||
        (!is_int($roleIndex) && !(is_string($roleIndex) && ctype_digit($roleIndex)))) {
        history_action_error(400, 'A valid history role and role index are required.');
    }
    $arguments[] = 'prune';
    $arguments[] = '--' . $role;
    $arguments[] = $action === 'cut' ? '--cut' : '--reduce';
    $arguments[] = (string) $roleIndex;
} elseif ($action === 'delete-below') {
    if (!is_int($index) && !(is_string($index) && ctype_digit($index))) {
        history_action_error(400, 'A history index is required.');
    }
    $arguments = ['history', 'delete', (string) $index . '-'];
} elseif ($action === 'clear') {
    $arguments[] = 'clear';
} elseif ($action === 'hide-turn') {
    $arguments = ['history', 'hide', 'turn'];
} elseif ($action === 'hide-all') {
    $arguments = ['history', 'hide', 'all'];
} elseif ($action === 'compact') {
    $arguments = ['history', 'compact'];
} elseif ($action === 'replace') {
    if (!is_int($index) && !(is_string($index) && ctype_digit($index))) {
        history_action_error(400, 'A history index is required.');
    }
    $arguments[] = 'replace';
    $arguments[] = (string) $index;
    $body = (string) ($input['content'] ?? '');
} else {
    history_action_error(400, 'Unknown history action.');
}

$process = proc_open(
    array_merge([maia_binary()], $arguments),
    [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
    $pipes,
    null,
    maia_environment()
);
if (!is_resource($process)) {
    history_action_error(500, 'Unable to start MAIA.');
}
if ($body !== '') {
    fwrite($pipes[0], $body);
}
fclose($pipes[0]);
$output = (string) stream_get_contents($pipes[1]);
fclose($pipes[1]);
$error = (string) stream_get_contents($pipes[2]);
fclose($pipes[2]);
$status = proc_close($process);
if ($status !== 0) {
    history_action_error(502, trim($error) ?: trim($output) ?: 'Unable to update history.');
}

echo json_encode(['ok' => true], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
