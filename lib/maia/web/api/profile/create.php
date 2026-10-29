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

function profile_create_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? 'POST') !== 'POST') {
    header('Allow: POST');
    profile_create_error(405, 'Method not allowed.');
}

$input = json_decode((string) (file_get_contents('php://input') ?: ''), true);
if (!is_array($input)) {
    profile_create_error(400, 'Invalid profile data.');
}

$name = trim((string) ($input['name'] ?? ''));
$description = (string) ($input['description'] ?? '');
if ($name === '') {
    profile_create_error(400, 'A profile name is required.');
}

$scope = trim((string) ($_GET['scope'] ?? 'home'));
if (!in_array($scope, ['session', 'workspace', 'profile', 'home'], true)) {
    profile_create_error(400, 'Invalid profile scope.');
}

// A profile page supplies a parent profile, but profile is not itself a
// storage scope. Store the child as parent%child in the scope where the
// parent profile is defined.
if ($scope === 'profile') {
    $parent = trim((string) ($_SERVER['HTTP_X_MAIA_PROFILE'] ?? $_SERVER['MAIA_URL_PROFILE'] ?? ''));
    if ($parent === '') {
        profile_create_error(400, 'A parent profile is required when creating from a profile page.');
    }

    $scopeProcess = proc_open(
        [maia_binary(), 'profile', '--scope'],
        [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
        $scopePipes,
        null,
        maia_environment()
    );
    if (!is_resource($scopeProcess)) {
        profile_create_error(500, 'Unable to resolve the parent profile scope.');
    }
    fclose($scopePipes[0]);
    $parentScope = trim((string) stream_get_contents($scopePipes[1]));
    fclose($scopePipes[1]);
    $scopeError = (string) stream_get_contents($scopePipes[2]);
    fclose($scopePipes[2]);
    $scopeStatus = proc_close($scopeProcess);
    if ($scopeStatus !== 0 || !in_array($parentScope, ['session', 'workspace', 'home'], true)) {
        profile_create_error(502, trim($scopeError) ?: 'Unable to resolve the parent profile scope.');
    }

    $name = $parent . '%' . $name;
    $scope = $parentScope;
}

$process = proc_open(
    [maia_binary(), 'profile', '--scope', $scope, 'create', $name, $description],
    [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
    $pipes,
    null,
    maia_environment()
);
if (!is_resource($process)) {
    profile_create_error(500, 'Unable to start MAIA.');
}
fclose($pipes[0]);
$output = (string) stream_get_contents($pipes[1]);
fclose($pipes[1]);
$error = (string) stream_get_contents($pipes[2]);
fclose($pipes[2]);
$status = proc_close($process);
if ($status !== 0) {
    profile_create_error(502, trim($error) ?: trim($output) ?: 'Unable to create the profile.');
}

echo json_encode([
    'ok' => true,
    'name' => $name,
    'message' => trim($output) ?: 'Profile created.',
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
