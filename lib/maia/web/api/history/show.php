<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 */

declare(strict_types=1);

require_once __DIR__ . '/../web.php';

header('Content-Type: application/json; charset=utf-8');

function history_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode([
        'ok' => false,
        'error' => $message,
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

/** Run MAIA without buffering its potentially huge JSON output in PHP memory. */
function history_stream_cli(array $arguments): never
{
    $process = proc_open(
        array_merge([getenv('MAIA_BIN') ?: 'maia'], $arguments),
        [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
        $pipes,
        null,
        maia_environment()
    );
    if (!is_resource($process)) {
        history_error(500, 'Unable to start MAIA.');
    }

    fclose($pipes[0]);
    $buffer = tmpfile();
    if ($buffer === false) {
        fclose($pipes[1]);
        $error = (string) stream_get_contents($pipes[2]);
        fclose($pipes[2]);
        proc_close($process);
        history_error(500, 'Unable to create a temporary history response buffer. ' . trim($error));
    }

    $copied = stream_copy_to_stream($pipes[1], $buffer);
    fclose($pipes[1]);
    $error = (string) stream_get_contents($pipes[2]);
    fclose($pipes[2]);
    $status = proc_close($process);
    if ($copied === false || $status !== 0) {
        fclose($buffer);
        history_error($status === 500 ? 500 : 502, trim($error) ?: 'MAIA returned an error.');
    }

    rewind($buffer);
    fpassthru($buffer);
    fclose($buffer);
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    header('Allow: POST');
    history_error(405, 'Method not allowed.');
}

$stickyOnly = (string) ($_GET['stickyOnly'] ?? '') === '1';
$range = trim((string) (file_get_contents('php://input') ?: ''));
if (!$stickyOnly && $range === '') {
    history_error(400, 'History range cannot be empty.');
}

if ($stickyOnly) {
    history_stream_cli(['history', '--raw', '--sticky']);
}
history_stream_cli(['history', '--raw', $range]);
