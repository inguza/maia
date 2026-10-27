<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */

declare(strict_types=1);

require_once __DIR__ . '/../web.php';

header('Content-Type: application/json; charset=utf-8');

function file_complete_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
    header('Allow: GET');
    file_complete_error(405, 'Method not allowed.');
}

$input = (string) ($_GET['path'] ?? '');
if (strpos($input, "\0") !== false || str_contains($input, "\n") || str_contains($input, "\r")) {
    file_complete_error(400, 'The file path contains an invalid character.');
}
if ($input !== '' && ($input[0] === '/' || preg_match('/^[A-Za-z]:[\\\/]/', $input))) {
    file_complete_error(400, 'Completion paths must be relative to the workspace root.');
}

$workspace = proc_open(
    [maia_web_binary(), 'workspace', 'show', '--raw'],
    [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
    $pipes,
    null,
    maia_web_environment()
);
if (!is_resource($workspace)) {
    file_complete_error(500, 'Unable to determine the workspace.');
}
fclose($pipes[0]);
$output = (string) stream_get_contents($pipes[1]);
fclose($pipes[1]);
$error = (string) stream_get_contents($pipes[2]);
fclose($pipes[2]);
$status = proc_close($workspace);
if ($status !== 0) {
    echo json_encode(['ok' => true, 'candidates' => []], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

$workspaceRoot = '';
foreach (preg_split('/\R/', $output) as $line) {
    if (preg_match('/^path:\s*(.*)$/', $line, $match)) {
        $workspaceRoot = trim($match[1]);
        break;
    }
}
$workspaceRoot = realpath($workspaceRoot);
if ($workspaceRoot === false || !is_dir($workspaceRoot) || !maia_web_path_within_home($workspaceRoot)) {
    echo json_encode(['ok' => true, 'candidates' => []], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

$directoryPart = str_ends_with($input, '/') ? $input : dirname($input);
$directoryPart = $directoryPart === '.' ? '' : $directoryPart;
$namePart = str_ends_with($input, '/') ? '' : basename($input);
$directoryCandidate = $directoryPart === ''
    ? $workspaceRoot
    : $workspaceRoot . DIRECTORY_SEPARATOR . str_replace(['/', '\\'], DIRECTORY_SEPARATOR, $directoryPart);
$directory = realpath($directoryCandidate);
if ($directory === false || !is_dir($directory) || !maia_web_path_within_home($directory)) {
    echo json_encode(['ok' => true, 'candidates' => []], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

$candidates = [];
foreach (scandir($directory) ?: [] as $entry) {
    if ($entry === '.' || $entry === '..' || ($namePart !== '' && !str_starts_with($entry, $namePart))) {
        continue;
    }
    $fullPath = $directory . DIRECTORY_SEPARATOR . $entry;
    if (!is_file($fullPath) && !is_dir($fullPath)) {
        continue;
    }
    if (!maia_web_path_within_home($fullPath)) {
        continue;
    }
    $relative = ($directoryPart === '' ? '' : rtrim(str_replace('\\', '/', $directoryPart), '/') . '/') . $entry;
    if (is_dir($fullPath)) {
        $relative .= '/';
    }
    $candidates[] = $relative;
}
sort($candidates, SORT_STRING);

echo json_encode(['ok' => true, 'input' => $input, 'candidates' => $candidates], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
