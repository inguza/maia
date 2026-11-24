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
$workspace = trim((string) ($input['workspace'] ?? ''));
if ($workspace !== '' && !maia_workspace_is_usable($workspace)) {
    session_create_error(403, 'The selected workspace is not available to the web interface.');
}
if ($source !== '') {
    $sourceWorkspace = maia_session_workspace($source) ?? '';
    if ($sourceWorkspace !== '' && !maia_workspace_is_usable($sourceWorkspace)) {
        session_create_error(403, 'The source session uses a workspace unavailable to the web interface.');
    }
}
$arguments = [maia_binary(), 'session', 'create'];
if ($workspace !== '') {
    array_push($arguments, '--workspace', $workspace);
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

// A CLI default can select a workspace that was not submitted in the request.
// If it falls outside the web policy, remove the just-created session rather
// than returning a successful session that the sidebar must hide.
$createdWorkspace = maia_session_workspace($name) ?? '';
if ($createdWorkspace !== '' && !maia_workspace_is_usable($createdWorkspace)) {
    $cleanup = proc_open(
        [maia_binary(), 'session', 'delete', $name],
        [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
        $cleanupPipes,
        null,
        maia_environment()
    );
    if (is_resource($cleanup)) {
        fclose($cleanupPipes[0]);
        stream_get_contents($cleanupPipes[1]);
        fclose($cleanupPipes[1]);
        $cleanupError = (string) stream_get_contents($cleanupPipes[2]);
        fclose($cleanupPipes[2]);
        $cleanupStatus = proc_close($cleanup);
        if ($cleanupStatus !== 0) {
            session_create_error(502, 'The session uses a workspace unavailable to the web interface and could not be cleaned up. '
                . trim($cleanupError));
        }
    } else {
        session_create_error(502, 'The session uses a workspace unavailable to the web interface and could not be cleaned up.');
    }
    session_create_error(403, 'The default workspace is not available to the web interface.');
}

echo json_encode([
    'ok' => true,
    'name' => $name,
    'source' => $source !== '' ? $source : null,
    'message' => trim($output) ?: 'Session created.',
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
