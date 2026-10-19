<?php

declare(strict_types=1);

require_once __DIR__ . '/../web.php';

header('Content-Type: application/json; charset=utf-8');

function files_remove_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode([
        'ok' => false,
        'error' => $message,
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? 'POST') !== 'POST') {
    header('Allow: POST');
    files_remove_error(405, 'Method not allowed.');
}

$entry = trim((string) (file_get_contents('php://input') ?: ''));
if ($entry === '') {
    files_remove_error(400, 'A known file entry is required.');
}
if (strpos($entry, "\0") !== false || str_contains($entry, "\n") || str_contains($entry, "\r")) {
    files_remove_error(400, 'The known file entry contains an invalid character.');
}

$process = proc_open(
    [maia_web_binary(), 'file', 'forget', $entry],
    [
        0 => ['pipe', 'r'],
        1 => ['pipe', 'w'],
        2 => ['pipe', 'w'],
    ],
    $pipes,
    null,
    maia_web_environment()
);

if (!is_resource($process)) {
    files_remove_error(500, 'Unable to start MAIA.');
}

fclose($pipes[0]);
$output = (string) stream_get_contents($pipes[1]);
fclose($pipes[1]);
$error = (string) stream_get_contents($pipes[2]);
fclose($pipes[2]);
$status = proc_close($process);

if ($status !== 0) {
    files_remove_error(502, trim($error) ?: trim($output) ?: 'Unable to forget the file.');
}

echo json_encode([
    'ok' => true,
    'path' => $entry,
    'message' => trim($output) ?: 'File forgotten.',
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
