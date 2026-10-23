<?php

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
        array_merge([maia_web_binary()], $arguments),
        [
            0 => ['pipe', 'r'],
            1 => ['pipe', 'w'],
            2 => ['pipe', 'w'],
        ],
        $pipes,
        $cwd,
        maia_web_environment()
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
$rootPrefix = rtrim($workspaceRoot, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR;
if ($boundaryPath !== false &&
    $boundaryPath !== $workspaceRoot &&
    !str_starts_with($boundaryPath, $rootPrefix)) {
    files_add_error(400, 'The file is outside the workspace root.');
}

$result = files_add_run(['file', 'add', $path], $workspaceRoot);
if ($result['status'] !== 0) {
    files_add_error(502, trim($result['error']) ?: trim($result['output']) ?: 'Unable to add the file.');
}

echo json_encode([
    'ok' => true,
    'path' => $path,
    'message' => trim($result['output']) ?: 'File added.',
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
