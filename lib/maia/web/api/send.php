<?php

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

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    header('Allow: POST');
    echo "Method not allowed.\n";
    exit;
}

$message = file_get_contents('php://input');
if ($message === false || trim($message) === '') {
    http_response_code(400);
    echo "Message cannot be empty.\n";
    exit;
}

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
    maia_web_environment()
);

if (!is_resource($process)) {
    http_response_code(500);
    echo "Unable to start MAIA.\n";
    exit;
}

fwrite($pipes[0], $message);
fclose($pipes[0]);

// Both pipes must be consumed while MAIA is running. Otherwise a full stderr
// pipe could block the process even when stdout is being read.
stream_set_blocking($pipes[1], false);
stream_set_blocking($pipes[2], false);

$stdoutOpen = true;
$stderrOpen = true;
$errorOutput = '';

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
    $ready = stream_select($read, $write, $except, null);
    if ($ready === false) {
        break;
    }

    foreach ($read as $stream) {
        // IMPORTANT! We want to do line-read and not read a large chunk.
	$chunk = fgets($stream);
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

        if ($stream === $pipes[1]) {
            echo $chunk;
            flush();
        } else {
            $errorOutput .= $chunk;
        }
    }
}

$exitCode = proc_close($process);

if ($exitCode !== 0) {
    $message = trim($errorOutput) !== ''
        ? trim($errorOutput)
        : 'MAIA returned an error.';
    echo "\n$message\n";
    flush();
}
