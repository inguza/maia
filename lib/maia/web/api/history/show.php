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
    echo json_encode([
        'ok' => false,
        'error' => $message,
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: POST');
    history_error(405, 'Method not allowed.');
}

$range = file_get_contents('php://input');
if ($range === false || trim($range) === '') {
    history_error(400, 'History range cannot be empty.');
}

$range = trim($range);
$maia = getenv('MAIA_BIN') ?: 'maia';
$descriptors = [
    0 => ['pipe', 'r'],
    1 => ['pipe', 'w'],
    2 => ['pipe', 'w'],
];

$process = proc_open(
    [$maia, 'history', '--raw', $range],
    $descriptors,
    $pipes,
    null,
    maia_environment()
);

if (!is_resource($process)) {
    history_error(500, 'Unable to start MAIA.');
}

fclose($pipes[0]);
$output = stream_get_contents($pipes[1]);
fclose($pipes[1]);
$errorOutput = stream_get_contents($pipes[2]);
fclose($pipes[2]);
$exitCode = proc_close($process);

if ($exitCode !== 0) {
    $message = trim($errorOutput) !== ''
        ? trim($errorOutput)
        : 'MAIA returned an error.';
    history_error(502, $message);
}

try {
    $history = json_decode($output, true, 512, JSON_THROW_ON_ERROR);
} catch (JsonException $exception) {
    history_error(502, 'MAIA returned invalid history data.');
}

if (!is_array($history)) {
    history_error(502, 'MAIA returned an invalid history list.');
}

$firstIndex = null;
$lastIndex = null;
$firstId = null;
$lastId = null;
if ($history !== []) {
    $first = $history[array_key_first($history)];
    $last = $history[array_key_last($history)];
    $firstIndex = $first['index'] ?? null;
    $lastIndex = $last['index'] ?? null;
    $firstId = $first['id'] ?? null;
    $lastId = $last['id'] ?? null;
}

echo json_encode([
    'ok' => true,
    'range' => $range,
    'firstIndex' => $firstIndex,
    'lastIndex' => $lastIndex,
    'firstId' => $firstId,
    'lastId' => $lastId,
    'items' => $history,
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
