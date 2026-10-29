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

function workspace_settings_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

function workspace_settings_run(array $arguments): array
{
    $process = proc_open(
        array_merge([maia_binary()], $arguments),
        [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
        $pipes,
        null,
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
    return ['output' => $output, 'error' => $error, 'status' => proc_close($process)];
}

function workspace_settings_home(): string
{
    return maia_workspace_base() ?? '';
}

function workspace_settings_display_path(string $path): string
{
    $resolved = realpath($path);
    return maia_relative_home_path($resolved !== false ? $resolved : $path);
}

function workspace_settings_absolute_path(string $path): string
{
    $home = workspace_settings_home();
    if ($path === '~') {
        return $home;
    }
    if (str_starts_with($path, '~' . DIRECTORY_SEPARATOR) || str_starts_with($path, '~/')) {
        return $home . DIRECTORY_SEPARATOR . ltrim(substr($path, 2), '/\\');
    }
    if ($path !== '' && $path[0] !== '/' && !preg_match('/^[A-Za-z]:[\\\\\/]/', $path)) {
        return $home . DIRECTORY_SEPARATOR . $path;
    }
    return $path;
}

function workspace_settings_values(string $name): array
{
    $result = workspace_settings_run(['workspace', 'show', '--raw', $name]);
    if ($result['status'] !== 0) {
        workspace_settings_error(502, trim($result['error']) ?: 'Unable to read workspace settings.');
    }
    $values = ['name' => $name, 'path' => '', 'filesets' => ''];
    foreach (preg_split('/\R/', $result['output']) as $line) {
        if (preg_match('/^([^:[:space:]]+):[[:space:]]?(.*)$/', $line, $match)) {
            if (array_key_exists($match[1], $values)) {
                $values[$match[1]] = trim($match[2]);
            }
        }
    }
    $values['path'] = workspace_settings_display_path($values['path']);
    return $values;
}

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$name = trim((string) ($_GET['name'] ?? ''));
if ($name === '') {
    $name = trim((string) ($_SERVER['HTTP_X_MAIA-WORKSPACE'] ?? ''));
}
if ($name === '' || !preg_match('/^[A-Za-z0-9_.%+-]+$/', $name)) {
    workspace_settings_error(400, 'A workspace name is required.');
}

if ($method === 'GET') {
    echo json_encode(['ok' => true] + workspace_settings_values($name), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}
if ($method !== 'POST') {
    header('Allow: GET, POST');
    workspace_settings_error(405, 'Method not allowed.');
}

$input = json_decode((string) (file_get_contents('php://input') ?: ''), true);
$path = trim((string) ($input['path'] ?? ''));
if (!is_array($input) || $path === '') {
    workspace_settings_error(400, 'A workspace path relative to the home directory is required.');
}
$path = workspace_settings_absolute_path($path);
$resolvedPath = realpath($path);
if ($resolvedPath === false || !is_dir($resolvedPath) || !maia_path_within_home($resolvedPath)) {
    workspace_settings_error(400, 'The workspace path must be an existing directory inside MAIA home.');
}
$path = $resolvedPath;
$result = workspace_settings_run(['workspace', 'set', '--path', $path, $name]);
if ($result['status'] !== 0) {
    workspace_settings_error(502, trim($result['error']) ?: trim($result['output']) ?: 'Unable to update workspace settings.');
}
echo json_encode(['ok' => true] + workspace_settings_values($name), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
