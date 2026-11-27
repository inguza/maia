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

function history_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

/** Stream one CLI-generated JSON array directly to the HTTP response. */
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
    stream_set_blocking($pipes[1], false);
    stream_set_blocking($pipes[2], false);

    $stdoutOpen = true;
    $stderrOpen = true;
    $sentOutput = false;
    $error = '';
    while ($stdoutOpen || $stderrOpen) {
        $read = [];
        if ($stdoutOpen) $read[] = $pipes[1];
        if ($stderrOpen) $read[] = $pipes[2];
        if ($read === []) break;
        $write = null;
        $except = null;
        $ready = @stream_select($read, $write, $except, 1);
        if ($ready === false) continue;
        if ($ready === 0) continue;
        foreach ($read as $stream) {
            $chunk = fread($stream, 65536);
            if ($stream === $pipes[1]) {
                if ($chunk !== false && $chunk !== '') {
                    echo $chunk;
                    flush();
                    $sentOutput = true;
                }
                if (feof($stream)) {
                    fclose($pipes[1]);
                    $stdoutOpen = false;
                }
            } else {
                if ($chunk !== false && $chunk !== '' && strlen($error) < 16384) {
                    $error .= substr($chunk, 0, 16384 - strlen($error));
                }
                if (feof($stream)) {
                    fclose($pipes[2]);
                    $stderrOpen = false;
                }
            }
        }
    }

    $status = proc_close($process);
    if ($status !== 0) {
        if ($sentOutput) {
            error_log('MAIA history JSON stream failed after output began: ' . trim($error));
            exit;
        }
        http_response_code(502);
        echo json_encode([
            'ok' => false,
            'error' => trim($error) ?: 'MAIA returned an error.',
        ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    }
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

// The endpoint returns the CLI's JSON array verbatim. The browser requests
// range and sticky arrays independently, then merges them without PHP holding
// either complete history array in memory.
while (ob_get_level() > 0) {
    ob_end_clean();
}
history_stream_cli($stickyOnly
    ? ['history', '--raw', '--sticky']
    : ['history', '--raw', $range]);
