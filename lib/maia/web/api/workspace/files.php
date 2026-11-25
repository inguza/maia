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

$workspaceName = trim((string) ($_SERVER['HTTP_X_MAIA_FILESYSTEM_WORKSPACE'] ?? $_SERVER['HTTP_X_MAIA_WORKSPACE'] ?? $_SERVER['MAIA_URL_WORKSPACE'] ?? ''));
if ($workspaceName === '' || !preg_match('/^[A-Za-z0-9_.%+\-]+$/', $workspaceName)) {
    workspace_files_error(400, 'A workspace is required.');
}
if (!maia_workspace_is_usable($workspaceName)) {
    workspace_files_error(404, 'Workspace is not available to the web interface.');
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

$workspaceRoot = maia_workspace_root_path($workspaceName);
if ($workspaceRoot === null) {
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
