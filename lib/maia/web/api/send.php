<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */

declare(strict_types=1);

require_once __DIR__ . '/web.php';

header('Content-Type: text/plain; charset=utf-8');
header('Cache-Control: no-cache, no-transform');
header('Content-Encoding: none');
header('X-Accel-Buffering: no');

// Send output to the client as soon as it is available.
while (ob_get_level() > 0) {
    ob_end_flush();
}
ob_implicit_flush(true);
flush();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    header('Allow: POST');
    echo "Method not allowed.\n";
    exit;
}

// Protocol line: acknowledge receipt before starting MAIA so the client can
// distinguish request acceptance from the command's output.
echo "MAIA-REQUEST-START\n";
flush();

$message = file_get_contents('php://input');
if ($message === false || trim($message) === '') {
    http_response_code(400);
    echo "Message cannot be empty.\n";
    exit;
}

// Protocol line: acknowledge receipt before starting MAIA so the client can
// distinguish request acceptance from the command's output.
echo "MAIA-REQUEST-RECEIVED\n";
flush();

$maia = getenv('MAIA_BIN') ?: 'maia';
$descriptors = [
    0 => ['pipe', 'r'],
    1 => ['pipe', 'w'],
    2 => ['pipe', 'w'],
];

$process = proc_open(
    [$maia, 'send', '+read'],
    $descriptors,
    $pipes,
    null,
    maia_environment()
);

if (!is_resource($process)) {
    echo "[ERROR] Unable to start MAIA.\n";
    flush();
    exit;
}

fwrite($pipes[0], $message);
fclose($pipes[0]);

// Make sure the webserver do not close down things because of timeout or because
// of client shutdown.
// No PHP execution time limit
set_time_limit(0);
// Continue if client disconnects
ignore_user_abort(true);

// Both pipes must be consumed while MAIA is running. Otherwise a full stderr
// pipe could block the process even when stdout is being read.
stream_set_blocking($pipes[1], false);
stream_set_blocking($pipes[2], false);

$stdoutOpen = true;
$stderrOpen = true;

while ($stdoutOpen || $stderrOpen) {
    $read = [];
    if ($stdoutOpen) {
        $read[] = $pipes[1];
    }
    if ($stderrOpen) {
        $read[] = $pipes[2];
    }

    if ($read === []) {
        break;
    }

    $write = null;
    $except = null;
    // Emit a small control heartbeat during long quiet periods so idle proxies
    // do not close a healthy streaming response. The browser strips this token.
    $ready = stream_select($read, $write, $except, 15);
    if ($ready === false) {
        break;
    }
    if ($ready === 0) {
        echo "\x1eMAIA-HEARTBEAT\x1f";
        flush();
        continue;
    }

    foreach ($read as $stream) {
        // Forward whichever pipe is ready immediately, preserving the order in
        // which stdout and stderr become available.
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

        echo $chunk;
        flush();
    }
}

$exitCode = proc_close($process);

if ($exitCode !== 0) {
    echo "[ERROR] Internal error [$exitCode]\n";
    flush();
}
