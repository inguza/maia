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
header('Cache-Control: no-store');

function session_lock_status_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
    header('Allow: GET');
    session_lock_status_error(405, 'Method not allowed.');
}

$session = trim((string) ($_SERVER['HTTP_X_MAIA_SESSION'] ?? $_SERVER['MAIA_URL_SESSION'] ?? ''));
if ($session === '') {
    session_lock_status_error(400, 'A session context is required.');
}

$process = proc_open(
    [maia_binary(), 'session', 'lock-status'],
    [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
    $pipes,
    null,
    maia_environment()
);
if (!is_resource($process)) {
    session_lock_status_error(502, 'Unable to check the session lock.');
}

fclose($pipes[0]);
$output = trim((string) stream_get_contents($pipes[1]));
fclose($pipes[1]);
$error = trim((string) stream_get_contents($pipes[2]));
fclose($pipes[2]);
$exitCode = proc_close($process);
if ($exitCode !== 0) {
    session_lock_status_error(502, $error !== '' ? $error : 'Unable to check the session lock.');
}

$result = json_decode($output, true);
if (!is_array($result) || !is_bool($result['locked'] ?? null)) {
    session_lock_status_error(502, 'MAIA returned an invalid session-lock status.');
}

echo json_encode(['ok' => true, 'locked' => $result['locked']], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
