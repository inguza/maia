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

function session_create_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? 'POST') !== 'POST') {
    header('Allow: POST');
    session_create_error(405, 'Method not allowed.');
}

$input = json_decode((string) (file_get_contents('php://input') ?: ''), true);
if (!is_array($input) || trim((string) ($input['name'] ?? '')) === '') {
    session_create_error(400, 'A session name is required.');
}

$name = trim((string) $input['name']);
$source = trim((string) ($input['source'] ?? ''));
if ($source !== '' && !preg_match('/^[A-Za-z0-9_.%+-]+$/', $source)) {
    session_create_error(400, 'Invalid source session name.');
}
$arguments = [maia_binary(), 'session', 'create'];
if (isset($input['workspace']) && (string) $input['workspace'] !== '') {
    array_push($arguments, '--workspace', (string) $input['workspace']);
}
if (isset($input['profile']) && (string) $input['profile'] !== '') {
    array_push($arguments, '--profile', (string) $input['profile']);
}
$arguments[] = $name;
if ($source !== '') {
    $arguments[] = $source;
}

$process = proc_open($arguments, [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes, null, maia_environment());
if (!is_resource($process)) {
    session_create_error(500, 'Unable to start MAIA.');
}
fclose($pipes[0]);
$output = (string) stream_get_contents($pipes[1]); fclose($pipes[1]);
$error = (string) stream_get_contents($pipes[2]); fclose($pipes[2]);
$status = proc_close($process);
if ($status !== 0) {
    session_create_error(502, trim($error) ?: trim($output) ?: 'Unable to create the session.');
}

echo json_encode([
    'ok' => true,
    'name' => $name,
    'source' => $source !== '' ? $source : null,
    'message' => trim($output) ?: 'Session created.',
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
