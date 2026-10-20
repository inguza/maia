<?php

declare(strict_types=1);

require_once __DIR__ . '/../web.php';

header('Content-Type: application/json; charset=utf-8');

function workspace_complete_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
    header('Allow: GET');
    workspace_complete_error(405, 'Method not allowed.');
}

$input = (string) ($_GET['path'] ?? '');
if (strpos($input, "\0") !== false || str_contains($input, "\n") || str_contains($input, "\r")) {
    workspace_complete_error(400, 'The workspace path contains an invalid character.');
}
if ($input !== '' && ($input[0] === '/' || preg_match('/^[A-Za-z]:[\\\/]/', $input))) {
    workspace_complete_error(400, 'Completion paths must be relative to the MAIA filesystem base.');
}

$base = realpath(maia_web_workspace_base() ?? '');
if ($base === false || !is_dir($base)) {
    echo json_encode(['ok' => true, 'candidates' => []], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

$directoryPart = str_ends_with($input, '/') ? $input : dirname($input);
$directoryPart = $directoryPart === '.' ? '' : $directoryPart;
$namePart = str_ends_with($input, '/') ? '' : basename($input);
$directoryCandidate = $directoryPart === ''
    ? $base
    : $base . DIRECTORY_SEPARATOR . str_replace(['/', '\\'], DIRECTORY_SEPARATOR, $directoryPart);
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
    if (!is_dir($fullPath) || !maia_web_path_within_home($fullPath)) {
        continue;
    }
    $relative = ($directoryPart === '' ? '' : rtrim(str_replace('\\', '/', $directoryPart), '/') . '/') . $entry . '/';
    $candidates[] = $relative;
}
sort($candidates, SORT_STRING);

echo json_encode(['ok' => true, 'input' => $input, 'candidates' => $candidates], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
