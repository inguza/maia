<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 */

declare(strict_types=1);

require_once __DIR__ . '/../web.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate');

function instruction_context_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

function instruction_context_run(array $arguments): array
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

function instruction_context_pattern(mixed $value): string
{
    $pattern = trim((string) $value);
    if ($pattern === '' || strlen($pattern) > 200 || !preg_match('/^[A-Za-z0-9_.%+*?@!()|\[\]-]+$/D', $pattern)) {
        instruction_context_error(400, 'Enter a valid instruction name or glob pattern.');
    }
    return $pattern;
}

function instruction_context_fields(string $file): array
{
    $content = @file_get_contents($file);
    if (!is_string($content) || !preg_match('/\A---[ \t]*\R(.*?)\R---(?:\R|$)/s', $content, $matches)) {
        return [];
    }
    $fields = [];
    foreach (preg_split('/\R/', $matches[1]) as $line) {
        if (preg_match('/^([A-Za-z0-9_-]+):\s*(.*?)\s*$/', $line, $field)) {
            $fields[$field[1]] = trim($field[2], " \t\"'");
        }
    }
    return $fields;
}

$scope = (string) ($_GET['scope'] ?? 'session');
if (!in_array($scope, ['session', 'workspace', 'profile', 'home'], true)) {
    instruction_context_error(400, 'Invalid instruction scope.');
}

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
if ($method === 'POST') {
    $input = json_decode((string) (file_get_contents('php://input') ?: ''), true);
    if (!is_array($input)) {
        instruction_context_error(400, 'Invalid instruction operation.');
    }
    $action = (string) ($input['action'] ?? '');
    if ($action === 'change') {
        $old = instruction_context_pattern($input['pattern'] ?? '');
        $replacement = instruction_context_pattern($input['replacement'] ?? '');
        $arguments = ['instruction', '--scope', $scope, 'change', $old, $replacement];
    } elseif (in_array($action, ['append', 'disable'], true)) {
        $pattern = instruction_context_pattern($input['pattern'] ?? '');
        $arguments = ['instruction', '--scope', $scope, $action === 'append' ? 'append' : 'forget', $pattern];
    } elseif (in_array($action, ['clear', 'delete'], true)) {
        $arguments = ['instruction', '--scope', $scope, $action];
    } else {
        instruction_context_error(400, 'Unknown instruction operation.');
    }
    $result = instruction_context_run($arguments);
    if ($result['status'] !== 0) {
        instruction_context_error(502, trim($result['error']) ?: trim($result['output']) ?: 'Unable to update instructions.');
    }
    echo json_encode(['ok' => true], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}
if ($method !== 'GET') {
    header('Allow: GET, POST');
    instruction_context_error(405, 'Method not allowed.');
}

$patternResult = instruction_context_run(['instruction', '--scope', $scope, 'view']);
if ($patternResult['status'] !== 0) {
    instruction_context_error(502, trim($patternResult['error']) ?: 'Unable to read instruction patterns.');
}
$patterns = array_values(array_unique(array_filter(array_map('trim', preg_split('/\R/', $patternResult['output'])))));
$scopeResult = instruction_context_run(['instruction', '--scope']);
$effectiveScope = $scopeResult['status'] === 0 ? (trim($scopeResult['output']) ?: 'default') : 'default';
$listResult = instruction_context_run(['instruction', 'list']);
if ($listResult['status'] !== 0) {
    instruction_context_error(502, trim($listResult['error']) ?: 'Unable to list instructions.');
}

$instructions = [];
foreach (preg_split('/\R/', $listResult['output']) as $line) {
    if (!preg_match('/^([* ])\s+(\S+)\s+(.+\/INSTRUCTION\.md)$/', rtrim($line, "\r"), $match)) {
        continue;
    }
    $fields = instruction_context_fields($match[3]);
    $loadable = $fields['loadable'] ?? '';
    $instructions[] = [
        'name' => $match[2],
        'description' => $fields['description'] ?? '',
        'autoload' => ($fields['autoload'] ?? '') === 'true',
        'conditions' => array_filter([
            'any-path' => $fields['any-path'] ?? '',
            'all-path' => $fields['all-path'] ?? '',
            'any-tool' => $fields['any-tool'] ?? '',
            'all-tool' => $fields['all-tool'] ?? '',
            'any-model' => $fields['any-model'] ?? '',
            'all-model' => $fields['all-model'] ?? '',
        ], static fn(string $value): bool => $value !== ''),
        'allowed' => $loadable === '' || $loadable === 'true',
        'selected' => $match[1] === '*',
    ];
}

echo json_encode([
    'ok' => true,
    'scope' => $effectiveScope,
    'targetScope' => $scope,
    'patterns' => $patterns,
    'instructions' => $instructions,
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
