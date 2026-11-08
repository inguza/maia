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

function approval_api_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

function approval_api_scope(): string
{
    $scope = (string) ($_GET['scope'] ?? 'session');
    if (!in_array($scope, ['session', 'workspace', 'profile', 'home'], true)) {
        approval_api_error(400, 'Invalid approval scope.');
    }
    return $scope;
}

function approval_api_run(array $arguments): array
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

function approval_api_rule(): string
{
    $rule = trim((string) (file_get_contents('php://input') ?: ''));
    if ($rule === '' || strpos($rule, "\0") !== false || str_contains($rule, "\n") || str_contains($rule, "\r") ||
        !preg_match('/^(.+):([^:]+)$/D', $rule)) {
        approval_api_error(400, 'Enter one approval rule in path-pattern:action form.');
    }
    $action = substr($rule, strrpos($rule, ':') + 1);
    if (!in_array($action, ['append', 'create', 'change', 'delete'], true)) {
        approval_api_error(400, "Unknown approval action '$action'. Valid actions: append, create, change, delete.");
    }
    return $rule;
}

function approval_api_require_post(): void
{
    if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
        header('Allow: POST');
        approval_api_error(405, 'Method not allowed.');
    }
}

function approval_api_execute(string $scope, string $command, ?string $rule = null): void
{
    $arguments = ['approve', '--scope', $scope, $command];
    if ($rule !== null) {
        $arguments[] = $rule;
    }
    $result = approval_api_run($arguments);
    if ($result['status'] !== 0) {
        approval_api_error(502, trim($result['error']) ?: trim($result['output']) ?: 'Approval operation failed.');
    }
    echo json_encode(['ok' => true], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}
