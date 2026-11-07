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

function config_context_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

function config_context_page_scope(): string
{
    $session = trim((string) ($_SERVER['MAIA_URL_SESSION'] ?? $_SERVER['HTTP_X_MAIA_SESSION'] ?? ''));
    if ($session !== '' && $session !== '_EMPTY_') return 'session';

    $profile = trim((string) ($_SERVER['MAIA_URL_PROFILE'] ?? $_SERVER['HTTP_X_MAIA_PROFILE'] ?? ''));
    if ($profile !== '') return 'profile';

    $workspace = trim((string) ($_SERVER['MAIA_URL_WORKSPACE'] ?? $_SERVER['HTTP_X_MAIA_WORKSPACE'] ?? ''));
    if ($workspace !== '') return 'workspace';

    $home = trim((string) ($_SERVER['MAIA_URL_HOME'] ?? $_SERVER['HTTP_X_MAIA_HOME'] ?? ''));
    if ($home !== '') return 'home';

    return 'session';
}

function config_context_scope_label(string $scope): string
{
    return match ($scope) {
        'session' => 'this session',
        'profile' => 'this profile',
        'workspace' => 'this workspace',
        'home' => 'home',
        'user' => 'user',
        'system' => 'system',
        'default' => 'built-in default',
        default => $scope,
    };
}

function config_context_environment(string $scope): array
{
    $environment = maia_environment();
    if ($scope !== 'session') {
        $environment['MAIA_SESSION'] = '_EMPTY_';
    }
    if ($scope === 'workspace' || $scope === 'home') {
        unset($environment['MAIA_PROFILE']);
    }
    if ($scope === 'home') {
        unset($environment['MAIA_WORKSPACE']);
    }
    return $environment;
}

/** @return array{output: string, error: string, status: int} */
function config_context_run(array $arguments, array $environment): array
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

function config_context_fail_run(array $result, string $fallback): void
{
    if ($result['status'] !== 0) {
        config_context_error(502, trim($result['error']) ?: trim($result['output']) ?: $fallback);
    }
}

function config_context_is_hidden_key(string $key): bool
{
    return in_array($key, [
        'additional_instruction_paths',
        'additional_skill_paths',
        'additional_tool_paths',
    ], true);
}

function config_context_parse_values(string $output): array
{
    $values = [];
    foreach (preg_split('/\R/', $output) as $line) {
        $separator = strpos($line, '=');
        if ($separator === false || $separator === 0) continue;
        $key = substr($line, 0, $separator);
        if (!preg_match('/^[A-Za-z0-9_]+$/', $key)) continue;
        $values[$key] = substr($line, $separator + 1);
    }
    return $values;
}

function config_context_parse_show(string $output): array
{
    $rows = [];
    foreach (preg_split('/\R/', $output) as $line) {
        $line = trim($line);
        if ($line === '' || str_starts_with($line, 'ENVIRONMENT NAME')) break;
        if (!preg_match('/^(\S+)\s+(\S+)\s+(.*)$/', $line, $match)) continue;
        if ($match[1] === 'CONFIG' && $match[2] === 'NAME') continue;
        if (preg_match('/^-+$/', $match[1])) continue;
        $rows[$match[1]] = ['scope' => $match[2], 'display' => $match[3]];
    }
    return $rows;
}

function config_context_values(string $scope, array $environment): array
{
    $keyResult = config_context_run(['config', '--all', 'list'], $environment);
    config_context_fail_run($keyResult, 'Unable to list configuration keys.');
    $knownKeys = [];
    foreach (preg_split('/\R/', $keyResult['output']) as $key) {
        $key = trim($key);
        if ($key !== '' && preg_match('/^[A-Za-z0-9_]+$/', $key) && !config_context_is_hidden_key($key)) {
            $knownKeys[$key] = true;
        }
    }

    $effectiveResult = config_context_run(['config', '--scope', $scope, 'get'], $environment);
    config_context_fail_run($effectiveResult, 'Unable to get effective configuration.');
    $effective = config_context_parse_values($effectiveResult['output']);
    foreach (array_keys($effective) as $key) {
        if (preg_match('/^(?:cost_(?:input|output)_|file_handling_mode_)/', $key) && !config_context_is_hidden_key($key)) {
            $knownKeys[$key] = true;
        }
    }

    $showResult = config_context_run(['config', '--scope', $scope, '--all', 'show'], $environment);
    config_context_fail_run($showResult, 'Unable to resolve configuration scopes.');
    $sources = config_context_parse_show($showResult['output']);

    $rows = [];
    foreach (array_keys($knownKeys) as $key) {
        if (!array_key_exists($key, $effective)) continue;
        $source = $sources[$key]['scope'] ?? '';
        if ($source === '') {
            // Dynamically added model-specific settings are intentionally supported
            // even when they are not in common.sh's built-in key list.
            $detail = config_context_run(['config', '--scope', $scope, '--all', 'show', $key], $environment);
            config_context_fail_run($detail, "Unable to resolve the source of '$key'.");
            $source = config_context_parse_show($detail['output'])[$key]['scope'] ?? 'default';
        }
        $rows[] = [
            'key' => $key,
            'value' => $effective[$key],
            'source' => $source,
        ];
    }

    usort($rows, static fn (array $a, array $b): int => strcmp($a['key'], $b['key']));
    $local = [];
    $other = [];
    foreach ($rows as $row) {
        if ($row['source'] === $scope) {
            $local[] = ['key' => $row['key'], 'value' => $row['value']];
        } else {
            $other[$row['source']][] = ['key' => $row['key'], 'value' => $row['value']];
        }
    }

    $scopeOrder = ['session', 'profile', 'workspace', 'home', 'user', 'system', 'default'];
    $otherScopes = [];
    foreach ($scopeOrder as $otherScope) {
        if ($otherScope === $scope || empty($other[$otherScope])) continue;
        $otherScopes[] = [
            'scope' => $otherScope,
            'label' => config_context_scope_label($otherScope),
            'values' => $other[$otherScope],
        ];
    }

    return [
        'scope' => $scope,
        'scopeLabel' => config_context_scope_label($scope),
        'local' => $local,
        'otherScopes' => $otherScopes,
    ];
}

function config_context_allowed_keys(string $scope, array $environment): array
{
    $keyResult = config_context_run(['config', '--all', 'list'], $environment);
    config_context_fail_run($keyResult, 'Unable to list configuration keys.');
    $allowed = [];
    foreach (preg_split('/\R/', $keyResult['output']) as $key) {
        $key = trim($key);
        if ($key !== '' && preg_match('/^[A-Za-z0-9_]+$/', $key) && !config_context_is_hidden_key($key)) {
            $allowed[$key] = true;
        }
    }
    $effectiveResult = config_context_run(['config', '--scope', $scope, 'get'], $environment);
    config_context_fail_run($effectiveResult, 'Unable to get effective configuration.');
    foreach (array_keys(config_context_parse_values($effectiveResult['output'])) as $key) {
        if (preg_match('/^(?:cost_(?:input|output)_|file_handling_mode_)/', $key)) $allowed[$key] = true;
    }
    return $allowed;
}

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$scope = config_context_page_scope();
$environment = config_context_environment($scope);

if ($method === 'GET') {
    echo json_encode(['ok' => true] + config_context_values($scope, $environment), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}
if ($method !== 'POST') {
    header('Allow: GET, POST');
    config_context_error(405, 'Method not allowed.');
}

$input = json_decode((string) (file_get_contents('php://input') ?: ''), true);
if (!is_array($input)) config_context_error(400, 'Invalid configuration operation.');
$action = (string) ($input['action'] ?? '');

if ($action === 'set') {
    $key = trim((string) ($input['key'] ?? ''));
    $value = $input['value'] ?? null;
    if (!is_string($value)) config_context_error(400, 'Configuration value must be text.');
    if ($value === '') config_context_error(400, 'An empty value cannot be saved; use Delete to remove the scope value.');
    $allowed = config_context_allowed_keys($scope, $environment);
    if (!isset($allowed[$key]) || config_context_is_hidden_key($key)) {
        config_context_error(400, 'This configuration key is not available in the web interface.');
    }
    if ($key === 'default_session_filesets') {
        $decoded = json_decode($value, true);
        if (is_array($decoded)) $value = implode(',', array_map('strval', $decoded));
    }
    $result = config_context_run(['config', '--scope', $scope, 'set', $key, $value], $environment);
    config_context_fail_run($result, 'Unable to save configuration value.');
} elseif ($action === 'delete') {
    $key = trim((string) ($input['key'] ?? ''));
    $before = config_context_values($scope, $environment);
    $localKeys = array_column($before['local'], 'key');
    if (!in_array($key, $localKeys, true) || config_context_is_hidden_key($key)) {
        config_context_error(400, 'This value is not set in the current scope.');
    }
    $result = config_context_run(['config', '--scope', $scope, 'unset', $key], $environment);
    config_context_fail_run($result, 'Unable to delete configuration value.');
} elseif ($action === 'add-model-setting') {
    $key = trim((string) ($input['key'] ?? ''));
    $value = trim((string) ($input['value'] ?? ''));
    if (!preg_match('/^file_handling_mode_[A-Za-z0-9_]+$/', $key)) {
        config_context_error(400, 'Use a parameter name like file_handling_mode_model_name.');
    }
    if ($value === '') {
        config_context_error(400, 'A value is required for the model-specific parameter.');
    }
    $result = config_context_run(['config', '--scope', $scope, 'set', $key, $value], $environment);
    config_context_fail_run($result, 'Unable to save model-specific parameter.');
} elseif ($action === 'add-cost') {
    $model = trim((string) ($input['model'] ?? ''));
    if ($model === '' || !preg_match('/^[A-Za-z0-9][A-Za-z0-9_.-]*$/', $model)) {
        config_context_error(400, 'Enter a valid model name.');
    }
    $suffix = strtolower(str_replace(['-', '.'], '_', $model));
    $costs = [];
    foreach (['inputCost' => 'cost_input_', 'outputCost' => 'cost_output_'] as $field => $prefix) {
        $value = trim((string) ($input[$field] ?? ''));
        if ($value === '') continue;
        if (!is_numeric($value) || (float) $value < 0) {
            config_context_error(400, 'Model costs must be non-negative numbers.');
        }
        $costs[$prefix . $suffix] = $value;
    }
    if ($costs === []) config_context_error(400, 'Enter an input cost, an output cost, or both.');
    foreach ($costs as $key => $value) {
        $result = config_context_run(['config', '--scope', $scope, 'set', $key, $value], $environment);
        config_context_fail_run($result, 'Unable to save model cost.');
    }
} else {
    config_context_error(400, 'Unknown configuration operation.');
}

echo json_encode(['ok' => true] + config_context_values($scope, $environment), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
