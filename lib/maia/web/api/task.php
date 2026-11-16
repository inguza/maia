<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 */

declare(strict_types=1);

require_once __DIR__ . '/web.php';

header('Content-Type: application/json; charset=utf-8');

function task_api_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

/** @return array{output: string, error: string, status: int} */
function task_api_run(array $arguments): array
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

/** @return array<string, mixed> */
function task_api_parse_pretty(string $text): array
{
    $fields = [];
    $current = null;
    foreach (preg_split('/\R/', $text) as $line) {
        if (str_starts_with($line, '  ') && $current !== null) {
            if (!is_array($fields[$current] ?? null)) {
                $previous = (string) ($fields[$current] ?? '');
                $fields[$current] = $previous === '' ? [] : [$previous];
            }
            $fields[$current][] = substr($line, 2);
            continue;
        }
        if (preg_match('/^([A-Za-z0-9_-]+):(?: ?(.*))?$/', $line, $match)) {
            $current = strtolower($match[1]);
            $value = (string) ($match[2] ?? '');
            $fields[$current] = $value === '' ? [] : $value;
        } else {
            $current = null;
        }
    }
    return $fields;
}

function task_api_scope(string $id): string
{
    if (preg_match('/^task-([0-9]+)$/', $id)) return 'session';
    if (preg_match('/^task-(workspace|profile)-/', $id, $match)) return $match[1];
    if (preg_match('/^task-session-/', $id)) return 'session';
    return 'unknown';
}

function task_api_list(): never
{
    $result = task_api_run(['task', 'list']);
    if ($result['status'] !== 0) {
        task_api_error(502, trim($result['error']) ?: trim($result['output']) ?: 'Unable to list tasks.');
    }

    $tasks = [];
    foreach (preg_split('/\R/', $result['output']) as $line) {
        if (!preg_match('/^([* ])\s+(\S+)/', $line, $match)) continue;
        $id = $match[2];
        if (!preg_match('/^[A-Za-z0-9_.+-]+$/', $id)) continue;
        $detail = task_api_run(['task', 'show', $id]);
        if ($detail['status'] !== 0) continue;
        $fields = task_api_parse_pretty($detail['output']);
        $description = $fields['description'] ?? [];
        $progress = $fields['progress'] ?? [];
        $tasks[] = [
            'id' => $id,
            'scope' => task_api_scope($id),
            'status' => is_string($fields['status'] ?? null) ? $fields['status'] : '',
            'version' => (string) ($fields['version'] ?? '1'),
            'description' => is_array($description) ? array_values($description) : [$description],
            'progress' => is_array($progress) ? array_values($progress) : [$progress],
            'loaded' => $match[1] === '*',
        ];
    }
    echo json_encode(['ok' => true, 'tasks' => $tasks], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

function task_api_text_lines(mixed $value, string $label): array
{
    if (is_string($value)) $value = preg_split('/\r\n|\n|\r/', $value);
    if (!is_array($value) || $value === []) task_api_error(400, "$label is required.");
    $lines = [];
    foreach ($value as $line) {
        if (!is_string($line) && !is_numeric($line)) task_api_error(400, "$label must contain text.");
        $line = (string) $line;
        if (str_contains($line, "\0")) task_api_error(400, "$label contains an invalid character.");
        $lines[] = $line;
    }
    while ($lines !== [] && trim((string) end($lines)) === '') array_pop($lines);
    if ($lines === [] || trim(implode('', $lines)) === '') task_api_error(400, "$label is required.");
    return $lines;
}

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
if ($method === 'GET') task_api_list();
if ($method !== 'POST') {
    header('Allow: GET, POST');
    task_api_error(405, 'Method not allowed.');
}

$body = json_decode((string) file_get_contents('php://input'), true);
if (!is_array($body)) task_api_error(400, 'Invalid JSON body.');
$action = trim((string) ($body['action'] ?? ''));
$id = trim((string) ($body['id'] ?? ''));
if ($id !== '' && !preg_match('/^[A-Za-z0-9_.+-]+$/', $id)) task_api_error(400, 'Invalid task ID.');

switch ($action) {
    case 'create':
        $scope = trim((string) ($body['scope'] ?? 'session'));
        if (!in_array($scope, ['session', 'workspace', 'profile'], true)) task_api_error(400, 'Invalid task scope.');
        $description = task_api_text_lines($body['description'] ?? null, 'Task description');
        $type = $scope === 'session' ? '--private' : '--shared';
        $created = task_api_run(['task', '--scope', $scope, 'create', $type, ...$description]);
        if ($created['status'] !== 0) task_api_error(502, trim($created['error']) ?: trim($created['output']) ?: 'Unable to create task.');
        preg_match('/\b(task-[A-Za-z0-9_.+-]+)\s*$/m', trim($created['output']), $match);
        echo json_encode(['ok' => true, 'id' => $match[1] ?? '', 'message' => trim($created['output'])], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
        exit;

    case 'update':
        if ($id === '') task_api_error(400, 'A task ID is required.');
        $version = trim((string) ($body['version'] ?? ''));
        if ($version === '' || !ctype_digit($version)) task_api_error(400, 'A valid task version is required.');
        $description = task_api_text_lines($body['description'] ?? null, 'Task description');
        $args = ['task', 'update', $id, $version, ...$description];
        break;

    case 'status':
        if ($id === '') task_api_error(400, 'A task ID is required.');
        $version = trim((string) ($body['version'] ?? ''));
        $status = trim((string) ($body['status'] ?? ''));
        if ($version === '' || !ctype_digit($version)) task_api_error(400, 'A valid task version is required.');
        if ($status === '' || preg_match('/[\r\n\0]/', $status)) task_api_error(400, 'A valid task status is required.');
        $args = ['task', 'mark', $id, $version, $status];
        break;

    case 'report':
        if ($id === '') task_api_error(400, 'A task ID is required.');
        $version = trim((string) ($body['version'] ?? ''));
        $report = trim((string) ($body['progress'] ?? ''));
        if ($version === '' || !ctype_digit($version)) task_api_error(400, 'A valid task version is required.');
        if ($report === '' || preg_match('/[\r\n\0]/', $report)) task_api_error(400, 'A one-line progress report is required.');
        $args = ['task', 'report', $id, $version, $report];
        break;

    case 'delete':
        if ($id === '') task_api_error(400, 'A task ID is required.');
        $args = ['task', 'remove', $id];
        break;

    case 'loaded':
        if ($id === '') task_api_error(400, 'A task ID is required.');
        $loaded = ($body['loaded'] ?? false) === true;
        $args = ['task', $loaded ? 'remember' : 'forget', $id];
        break;

    default:
        task_api_error(400, 'Unsupported task action.');
}

$updated = task_api_run($args);
if ($updated['status'] !== 0) {
    $message = trim($updated['error']) ?: trim($updated['output']) ?: 'Unable to update task.';
    task_api_error(str_contains(strtolower($message), 'version mismatch') ? 409 : 502, $message);
}
echo json_encode(['ok' => true, 'message' => trim($updated['output']) ?: 'Task updated.'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
