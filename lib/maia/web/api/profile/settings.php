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

function profile_settings_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

function profile_settings_run(array $arguments): array
{
    $process = proc_open(
        array_merge([maia_web_binary()], $arguments),
        [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
        $pipes,
        null,
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
    return ['output' => $output, 'error' => $error, 'status' => proc_close($process)];
}

function profile_settings_values(string $name): array
{
    $result = profile_settings_run(['profile', 'show', '--raw', $name]);
    if ($result['status'] !== 0) {
        profile_settings_error(502, trim($result['error']) ?: trim($result['output']) ?: 'Unable to read profile settings.');
    }
    $description = '';
    foreach (preg_split('/\R/', $result['output']) as $line) {
        if (preg_match('/^description:[[:space:]]?(.*)$/', $line, $match)) {
            $description = $match[1];
            break;
        }
    }
    $scopeResult = profile_settings_run(['profile', '--scope']);
    $scope = trim($scopeResult['output']);
    if ($scopeResult['status'] !== 0 || $scope === '') {
        $scope = 'home';
    }
    return ['name' => $name, 'description' => $description, 'scope' => $scope];
}

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$name = trim((string) ($_GET['name'] ?? ''));
if ($name === '') {
    $name = trim((string) ($_SERVER['HTTP_X_MAIA_PROFILE'] ?? ''));
}
if ($name === '' || !preg_match('/^[A-Za-z0-9_.%+\-]+$/', $name)) {
    profile_settings_error(400, 'A profile name is required.');
}

if ($method === 'GET') {
    echo json_encode(['ok' => true] + profile_settings_values($name), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}
if ($method !== 'POST') {
    header('Allow: GET, POST');
    profile_settings_error(405, 'Method not allowed.');
}

$input = json_decode((string) (file_get_contents('php://input') ?: ''), true);
$description = (string) ($input['description'] ?? '');
if (!is_array($input)) {
    profile_settings_error(400, 'Invalid profile settings.');
}
$result = profile_settings_run(['profile', 'set', '--description', $description, $name]);
if ($result['status'] !== 0) {
    profile_settings_error(502, trim($result['error']) ?: trim($result['output']) ?: 'Unable to update profile settings.');
}
echo json_encode(['ok' => true] + profile_settings_values($name), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
