<?php

declare(strict_types=1);

require_once __DIR__ . '/../web.php';

header('Content-Type: application/json; charset=utf-8');

function workspace_files_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
    header('Allow: GET');
    workspace_files_error(405, 'Method not allowed.');
}

$workspaceName = trim((string) ($_SERVER['HTTP_X_MAIA_WORKSPACE'] ?? $_SERVER['MAIA_URL_WORKSPACE'] ?? ''));
if ($workspaceName === '' || !preg_match('/^[A-Za-z0-9_.%+\-]+$/', $workspaceName)) {
    workspace_files_error(400, 'A workspace is required.');
}

$inputPath = (string) ($_GET['path'] ?? '');
if (strpos($inputPath, "\0") !== false || str_contains($inputPath, "\n") || str_contains($inputPath, "\r")) {
    workspace_files_error(400, 'Invalid workspace path.');
}
$inputPath = str_replace('\\', '/', $inputPath);
if ($inputPath !== '' && ($inputPath[0] === '/' || preg_match('/^[A-Za-z]:\//', $inputPath))) {
    workspace_files_error(400, 'Workspace paths must be relative.');
}
$parts = [];
foreach (explode('/', $inputPath) as $part) {
    if ($part === '' || $part === '.') {
        continue;
    }
    if ($part === '..') {
        workspace_files_error(400, 'Path traversal is not allowed.');
    }
    $parts[] = $part;
}
$relativePath = implode('/', $parts);

$process = proc_open(
    [maia_web_binary(), 'workspace', 'show', '--raw', $workspaceName],
    [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
    $pipes,
    null,
    maia_web_environment()
);
if (!is_resource($process)) {
    workspace_files_error(500, 'Unable to determine the workspace.');
}
fclose($pipes[0]);
$output = (string) stream_get_contents($pipes[1]);
fclose($pipes[1]);
$diagnostic = (string) stream_get_contents($pipes[2]);
fclose($pipes[2]);
$status = proc_close($process);
if ($status !== 0) {
    workspace_files_error(502, trim($diagnostic) ?: 'Unable to determine the workspace.');
}

$workspaceRoot = '';
foreach (preg_split('/\R/', $output) as $line) {
    if (preg_match('/^path:\s*(.*)$/', $line, $match)) {
        $workspaceRoot = trim($match[1]);
        break;
    }
}
$workspaceRoot = realpath(maia_web_expand_home_path($workspaceRoot));
if ($workspaceRoot === false || !is_dir($workspaceRoot)) {
    workspace_files_error(403, 'The workspace root is unavailable.');
}

$candidatePath = $relativePath === ''
    ? $workspaceRoot
    : $workspaceRoot . DIRECTORY_SEPARATOR . $relativePath;
$directory = $relativePath === '' ? $workspaceRoot : realpath($candidatePath);
$rootPrefix = rtrim($workspaceRoot, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR;
$withinRoot = $directory !== false &&
    ($directory === $workspaceRoot || str_starts_with($directory, $rootPrefix));
if ($directory === false || !is_dir($directory)) {
    workspace_files_error(404, 'Workspace directory not found.');
}
if (!$withinRoot) {
    workspace_files_error(403, 'The directory is outside the workspace.');
}

$entries = [];
foreach (scandir($directory) ?: [] as $name) {
    if ($name === '.' || $name === '..') {
        continue;
    }
    $fullPath = $directory . DIRECTORY_SEPARATOR . $name;
    $resolved = realpath($fullPath);
    if ($resolved === false || ($resolved !== $workspaceRoot && !str_starts_with($resolved, $rootPrefix))) {
        continue;
    }
    $isDirectory = is_dir($fullPath);
    $children = $isDirectory ? @scandir($fullPath) : false;
    $isEmptyDirectory = $isDirectory && $children !== false && count(array_diff($children, ['.', '..'])) === 0;
    $entries[] = [
        'name' => $name,
        'path' => ($relativePath === '' ? '' : $relativePath . '/') . $name,
        'type' => $isDirectory ? 'directory' : 'file',
        'size' => $isDirectory ? null : (is_file($fullPath) ? filesize($fullPath) : null),
        'modified' => @filemtime($fullPath) ?: null,
        'empty' => $isEmptyDirectory,
    ];
}
usort($entries, static function (array $a, array $b): int {
    return [$a['type'] !== 'directory', strtolower($a['name'])] <=> [$b['type'] !== 'directory', strtolower($b['name'])];
});

echo json_encode([
    'ok' => true,
    'workspace' => $workspaceName,
    'path' => $relativePath,
    'entries' => $entries,
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
