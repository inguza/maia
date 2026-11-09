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

function workspace_create_error(int $status, string $message, string $code = ''): never
{
    http_response_code($status);
    $response = ['ok' => false, 'error' => $message];
    if ($code !== '') $response['code'] = $code;
    echo json_encode($response, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

/** Resolve a missing directory path safely beneath the configured workspace base. */
function workspace_create_missing_path(string $path): ?string
{
    $base = maia_workspace_base();
    $resolvedBase = $base === null ? false : realpath($base);
    if ($resolvedBase === false) return null;

    $path = maia_expand_home_path($path);
    $normalized = str_replace('\\\\', '/', $path);
    if (preg_match('#(^|/)\\.\\.(/|$)#', $normalized)) return null;

    $candidate = rtrim($path, DIRECTORY_SEPARATOR . '/\\\\');
    if ($candidate === '') return null;
    $missingParts = [];
    while (!file_exists($candidate) && !is_link($candidate)) {
        $part = basename($candidate);
        if ($part === '' || $part === '.' || $part === '..') return null;
        array_unshift($missingParts, $part);
        $parent = dirname($candidate);
        if ($parent === $candidate) return null;
        $candidate = $parent;
    }

    $resolvedParent = realpath($candidate);
    if ($resolvedParent === false || !is_dir($resolvedParent) || !maia_path_within_home($resolvedParent)) return null;
    $target = $resolvedParent;
    foreach ($missingParts as $part) $target .= DIRECTORY_SEPARATOR . $part;

    $prefix = rtrim($resolvedBase, DIRECTORY_SEPARATOR . '/\\\\') . DIRECTORY_SEPARATOR;
    if ($target !== $resolvedBase && !str_starts_with($target, $prefix)) return null;
    return $target;
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
$createPath = ($input['createPath'] ?? false) === true;
$path = maia_expand_home_path($path);
$resolvedPath = realpath($path);
if ($resolvedPath === false) {
    // Always ask first when the target is missing. Validate containment only
    // after consent, immediately before creating the directory.
    if (!$createPath) {
        workspace_create_error(409, 'The workspace directory does not exist.', 'workspace_path_missing');
    }
    $directoryToCreate = workspace_create_missing_path($path);
    if ($directoryToCreate === null) {
        workspace_create_error(400, 'The workspace path must be inside MAIA home and may not traverse above it.');
    }
    if (!is_dir($directoryToCreate) && !@mkdir($directoryToCreate, 0775, true) && !is_dir($directoryToCreate)) {
        workspace_create_error(500, 'Unable to create the workspace directory.');
    }
    $resolvedPath = realpath($directoryToCreate);
}
if ($resolvedPath === false || !is_dir($resolvedPath) || !maia_path_within_home($resolvedPath)) {
    workspace_create_error(400, 'The workspace path must be an existing directory inside MAIA home.');
}
$path = $resolvedPath;

$process = proc_open(
    [maia_binary(), 'workspace', 'create', '--path', $path, $name],
    [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
    $pipes,
    null,
    maia_environment()
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
