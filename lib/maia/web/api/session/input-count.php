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

function session_input_count_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
    header('Allow: POST');
    session_input_count_error(405, 'Method not allowed.');
}

$session = maia_selected_session();
if ($session === null || !preg_match('/^[A-Za-z0-9_.%+\\-]+$/', $session) || $session === '_EMPTY_') {
    session_input_count_error(400, 'A valid session context is required.');
}

$draft = file_get_contents('php://input');
if ($draft === false) {
    session_input_count_error(400, 'Unable to read the draft text.');
}

set_time_limit(0);
$process = proc_open(
    [maia_binary(), 'send', '--count', '+read'],
    [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
    $pipes,
    null,
    maia_environment()
);
if (!is_resource($process)) {
    session_input_count_error(502, 'Unable to start MAIA token counting.');
}

fwrite($pipes[0], $draft);
fclose($pipes[0]);
ignore_user_abort(true);
stream_set_blocking($pipes[1], false);
stream_set_blocking($pipes[2], false);
$stdoutOpen = true;
$stderrOpen = true;
$output = '';
$error = '';
while ($stdoutOpen || $stderrOpen) {
    $read = [];
    if ($stdoutOpen) $read[] = $pipes[1];
    if ($stderrOpen) $read[] = $pipes[2];
    $write = null;
    $except = null;
    $ready = stream_select($read, $write, $except, 1);
    if ($ready === false) break;
    if ($ready === 0) continue;
    foreach ($read as $stream) {
        $chunk = fread($stream, 8192);
        if ($chunk === false || $chunk === '') {
            if (feof($stream)) {
                if ($stream === $pipes[1]) {
                    $stdoutOpen = false;
                    fclose($pipes[1]);
                } else {
                    $stderrOpen = false;
                    fclose($pipes[2]);
                }
            }
            continue;
        }
        if ($stream === $pipes[1]) $output .= $chunk;
        else $error .= $chunk;
    }
}
if ($stdoutOpen) fclose($pipes[1]);
if ($stderrOpen) fclose($pipes[2]);
$error = trim($error);
$output = trim($output);
$exitCode = proc_close($process);

if ($exitCode !== 0) {
    session_input_count_error(502, $error !== '' ? $error : 'Unable to count input tokens.');
}
if (!preg_match('/^\\d+$/', $output)) {
    session_input_count_error(502, 'MAIA returned an invalid input-token count.');
}

echo json_encode(['ok' => true, 'input_tokens' => (int) $output], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
