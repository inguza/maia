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

function behavior_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

/** Determine the only scope this page is allowed to edit. */
function behavior_page_scope(): string
{
    $session = trim((string) ($_SERVER['MAIA_URL_SESSION'] ?? ''));
    if ($session === '') {
        $session = trim((string) ($_SERVER['HTTP_X_MAIA_SESSION'] ?? ''));
    }
    if ($session !== '' && $session !== '_EMPTY_') {
        return 'session';
    }

    $profile = trim((string) ($_SERVER['HTTP_X_MAIA_PROFILE'] ?? $_SERVER['MAIA_URL_PROFILE'] ?? ''));
    if ($profile !== '') {
        return 'profile';
    }

    $workspace = trim((string) ($_SERVER['HTTP_X_MAIA_WORKSPACE'] ?? $_SERVER['MAIA_URL_WORKSPACE'] ?? ''));
    if ($workspace !== '') {
        return 'workspace';
    }

    $home = trim((string) ($_SERVER['HTTP_X_MAIA_HOME'] ?? $_SERVER['MAIA_URL_HOME'] ?? ''));
    if ($home !== '') {
        return 'home';
    }

    return 'session';
}

/** Build the environment so implicit-source lookup starts at the page's scope. */
function behavior_environment(string $scope): array
{
    $environment = maia_environment();
    if ($scope !== 'session') {
        $environment['MAIA_SESSION'] = '_EMPTY_';
    }
    if ($scope === 'workspace' || $scope === 'home') {
        $environment['MAIA_PROFILE'] = '_EMPTY_';
    }
    if ($scope === 'home') {
        $environment['MAIA_WORKSPACE'] = '_EMPTY_';
    }
    return $environment;
}

/** @return array{output: string, error: string, status: int} */
function behavior_run(array $arguments, array $environment): array
{
    $process = proc_open(
        array_merge([maia_binary()], $arguments),
        [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
        $pipes,
        null,
        $environment
    );
    if (!is_resource($process)) {
        return ['output' => '', 'error' => 'Unable to start MAIA.', 'status' => 1];
    }
    fclose($pipes[0]);
    $output = (string) stream_get_contents($pipes[1]);
    fclose($pipes[1]);
    $error = (string) stream_get_contents($pipes[2]);
    fclose($pipes[2]);
    return ['output' => $output, 'error' => $error, 'status' => proc_close($process)];
}

/** @return array{scope: string, sourceScope: string, local: bool, text: string} */
function behavior_values(string $scope, array $environment): array
{
    $prompt = behavior_run(['system', '--type', 'system', '--scope', $scope, 'show'], $environment);
    if ($prompt['status'] !== 0) {
        behavior_error(502, trim($prompt['error']) ?: trim($prompt['output']) ?: 'Unable to read behavior settings.');
    }

    // With --scope but no value, the existing CLI reports the scope supplying
    // the current prompt (or "default" for the built-in fallback).
    $source = behavior_run(['system', '--type', 'system', '--scope'], $environment);
    if ($source['status'] !== 0) {
        behavior_error(502, trim($source['error']) ?: trim($source['output']) ?: 'Unable to resolve behavior source.');
    }
    $sourceScope = trim($source['output']) ?: 'default';

    return [
        'scope' => $scope,
        'sourceScope' => $sourceScope,
        'local' => $sourceScope === $scope,
        'text' => $prompt['output'],
    ];
}

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$scope = behavior_page_scope();
$environment = behavior_environment($scope);

if ($method === 'GET') {
    echo json_encode(['ok' => true] + behavior_values($scope, $environment), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}
if ($method !== 'POST') {
    header('Allow: GET, POST');
    behavior_error(405, 'Method not allowed.');
}

$input = json_decode((string) (file_get_contents('php://input') ?: ''), true);
if (!is_array($input)) {
    behavior_error(400, 'Invalid behavior settings.');
}
$action = (string) ($input['action'] ?? '');
if ($action === 'reset') {
    $result = behavior_run(['system', '--type', 'system', '--scope', $scope, 'delete'], $environment);
} elseif ($action === 'save') {
    if (!is_string($input['text'] ?? null)) {
        behavior_error(400, 'Behavior text must be a string.');
    }
    $text = $input['text'];
    if (str_contains($text, "\0")) {
        behavior_error(400, 'Behavior text contains an invalid character.');
    }
    if ($text === '') {
        $result = behavior_run(['system', '--type', 'system', '--scope', $scope, 'clear'], $environment);
    } else {
        $temporaryFile = tempnam(sys_get_temp_dir(), 'maia-behavior-');
        if ($temporaryFile === false || file_put_contents($temporaryFile, $text, LOCK_EX) === false) {
            if (is_string($temporaryFile)) {
                @unlink($temporaryFile);
            }
            behavior_error(500, 'Unable to prepare behavior text.');
        }
        $result = behavior_run(
            ['system', '--type', 'system', '--scope', $scope, 'replace', '=' . $temporaryFile],
            $environment
        );
        @unlink($temporaryFile);
    }
} else {
    behavior_error(400, 'Unknown behavior operation.');
}

if ($result['status'] !== 0) {
    behavior_error(502, trim($result['error']) ?: trim($result['output']) ?: 'Unable to update behavior settings.');
}
echo json_encode(['ok' => true] + behavior_values($scope, $environment), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
