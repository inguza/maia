<?php

declare(strict_types=1);

require_once __DIR__ . '/../web.php';

header('Content-Type: application/json; charset=utf-8');

function tool_append_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? 'POST') !== 'POST') {
    header('Allow: POST');
    tool_append_error(405, 'Method not allowed.');
}

$pattern = trim((string) (file_get_contents('php://input') ?: ''));
if ($pattern === '' || strpos($pattern, "\0") !== false || str_contains($pattern, "\n") || str_contains($pattern, "\r")) {
    tool_append_error(400, 'A tool pattern is required.');
}

$process = proc_open(
    [maia_web_binary(), 'tool', '--scope', (string) ($_GET['scope'] ?? 'session'), 'append', $pattern],
    [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
    $pipes,
    null,
    maia_web_environment()
);
if (!is_resource($process)) {
    tool_append_error(500, 'Unable to start MAIA.');
}
fclose($pipes[0]);
$output = (string) stream_get_contents($pipes[1]);
fclose($pipes[1]);
$error = (string) stream_get_contents($pipes[2]);
fclose($pipes[2]);
$status = proc_close($process);
if ($status !== 0) {
    tool_append_error(502, trim($error) ?: trim($output) ?: 'Unable to add the tool pattern.');
}

echo json_encode(['ok' => true, 'pattern' => $pattern], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
