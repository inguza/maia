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

function files_add_error(int $status, string $message): never
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
    files_add_error(405, 'Method not allowed.');
}

$path = trim((string) (file_get_contents('php://input') ?: ''));
if ($path === '') {
    files_add_error(400, 'A file path is required.');
}
if (strpos($path, "\0") !== false || str_contains($path, "\n") || str_contains($path, "\r")) {
    files_add_error(400, 'The file path contains an invalid character.');
}

/** @return array{output: string, error: string, status: int} */
function files_add_run(array $arguments, ?string $cwd = null): array
{
    $process = proc_open(
        array_merge([maia_binary()], $arguments),
        [
            0 => ['pipe', 'r'],
            1 => ['pipe', 'w'],
            2 => ['pipe', 'w'],
        ],
        $pipes,
        $cwd,
        maia_environment()
    );

    if (!is_resource($process)) {
        return ['output' => '', 'error' => 'Unable to start MAIA.', 'status' => 1];
    }

    fclose($pipes[0]);
    $output = (string) stream_get_contents($pipes[1]);
    fclose($pipes[1]);
    $error = (string) stream_get_contents($pipes[2]);
    fclose($pipes[2]);

    return [
        'output' => $output,
        'error' => $error,
        'status' => proc_close($process),
    ];
}

$workspace = files_add_run(['workspace', 'show', '--raw']);
if ($workspace['status'] !== 0) {
    files_add_error(502, trim($workspace['error']) ?: 'Unable to determine the workspace.');
}

$workspaceRoot = null;
foreach (preg_split('/\R/', $workspace['output']) as $line) {
    if (preg_match('/^path:\s*(.*)$/', $line, $match)) {
        $workspaceRoot = trim($match[1]);
        break;
    }
}
if ($workspaceRoot === null || $workspaceRoot === '') {
    files_add_error(400, 'The selected session has no workspace root.');
}

$workspaceRoot = realpath($workspaceRoot);
if ($workspaceRoot === false || !is_dir($workspaceRoot)) {
    files_add_error(400, 'The workspace root does not exist.');
}
// Expand local shell-style file patterns here: unlike a shell, the Files panel
// sends its input as a literal argument to the CLI.
$globPath = $path;
$metadataSuffix = '';
$pipePosition = strpos($globPath, '|');
if ($pipePosition !== false) {
    $metadataSuffix = substr($globPath, $pipePosition);
    $globPath = substr($globPath, 0, $pipePosition);
}
$colonPosition = strpos($globPath, ':');
if ($colonPosition !== false) {
    $metadataSuffix = substr($globPath, $colonPosition) . $metadataSuffix;
    $globPath = substr($globPath, 0, $colonPosition);
}
$hasGlob = strpbrk($globPath, '*?[') !== false;
$rootPrefix = rtrim($workspaceRoot, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR;
$addPaths = [];
$relativePaths = [];

if ($hasGlob) {
    $candidate = $globPath;
    if ($candidate === '' || ($candidate[0] !== '/' && !preg_match('/^[A-Za-z]:[\\\/]/', $candidate))) {
        $candidate = $workspaceRoot . DIRECTORY_SEPARATOR . $candidate;
    }

    foreach (glob($candidate) ?: [] as $match) {
        $resolvedMatch = realpath($match);
        if ($resolvedMatch === false || !is_file($resolvedMatch)) {
            continue;
        }
        if ($resolvedMatch !== $workspaceRoot && !str_starts_with($resolvedMatch, $rootPrefix)) {
            files_add_error(400, 'The file pattern matched a path outside the workspace root.');
        }
        $relativePaths[] = str_replace(DIRECTORY_SEPARATOR, '/', substr($resolvedMatch, strlen($rootPrefix))) . $metadataSuffix;
        $addPaths[] = $resolvedMatch . $metadataSuffix;
    }

    if ($addPaths === []) {
        files_add_error(400, 'The file pattern did not match any files in the workspace.');
    }
} else {
    // Keep the boundary check here because the CLI accepts paths outside the
    // workspace. File existence, file type, and workspace-relative conversion
    // remain the responsibility of `maia file add`.
    $candidate = $path;
    if ($candidate === '' || ($candidate[0] !== '/' && !preg_match('/^[A-Za-z]:[\\\/]/', $candidate))) {
        $candidate = $workspaceRoot . DIRECTORY_SEPARATOR . $candidate;
    }
    $resolvedCandidate = realpath($candidate);
    $resolvedParent = realpath(dirname($candidate));
    $boundaryPath = $resolvedCandidate !== false ? $resolvedCandidate : $resolvedParent;
    if ($boundaryPath !== false &&
        $boundaryPath !== $workspaceRoot &&
        !str_starts_with($boundaryPath, $rootPrefix)) {
        files_add_error(400, 'The file is outside the workspace root.');
    }
    $addPaths = [$path];
    $relativePaths = [$path];
}

$result = files_add_run(array_merge(['file', 'add'], $addPaths), $workspaceRoot);
if ($result['status'] !== 0) {
    files_add_error(502, trim($result['error']) ?: trim($result['output']) ?: 'Unable to add the file.');
}

echo json_encode([
    'ok' => true,
    'path' => $path,
    'paths' => $relativePaths,
    'message' => trim($result['output']) ?: 'File added.',
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
