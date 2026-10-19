<?php

declare(strict_types=1);

require_once __DIR__ . '/../web.php';

header('Content-Type: application/json; charset=utf-8');

function workspace_create_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? 'POST') !== 'POST') {
    header('Allow: POST');
    workspace_create_error(405, 'Method not allowed.');
}

$input = json_decode((string) (file_get_contents('php://input') ?: ''), true);
$name = trim((string) ($input['name'] ?? ''));
$path = trim((string) ($input['path'] ?? ''));
if (!is_array($input) || $name === '') {
    workspace_create_error(400, 'A workspace name is required.');
}
if ($path === '') {
    workspace_create_error(400, 'A workspace path is required.');
}
$path = maia_web_expand_home_path($path);
$resolvedPath = realpath($path);
if ($resolvedPath === false || !is_dir($resolvedPath) || !maia_web_path_within_home($resolvedPath)) {
    workspace_create_error(400, 'The workspace path must be an existing directory inside MAIA home.');
}
$path = $resolvedPath;

$process = proc_open(
    [maia_web_binary(), 'workspace', 'create', '--path', $path, $name],
    [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
    $pipes,
    null,
    maia_web_environment()
);
if (!is_resource($process)) {
    workspace_create_error(500, 'Unable to start MAIA.');
}
fclose($pipes[0]);
$output = (string) stream_get_contents($pipes[1]); fclose($pipes[1]);
$error = (string) stream_get_contents($pipes[2]); fclose($pipes[2]);
$status = proc_close($process);
if ($status !== 0) {
    workspace_create_error(502, trim($error) ?: trim($output) ?: 'Unable to create the workspace.');
}

echo json_encode(['ok' => true, 'name' => $name, 'message' => trim($output) ?: 'Workspace created.'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
