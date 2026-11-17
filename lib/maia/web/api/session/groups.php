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

maia_validate_environment();
maia_require_auth();
if (session_status() === PHP_SESSION_ACTIVE) {
    session_write_close();
}

header('Content-Type: application/json; charset=utf-8');

function session_groups_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

/** @return array{status: int, output: string, error: string} */
function session_groups_run(array $arguments): array
{
    $process = proc_open(
        array_merge([maia_binary()], $arguments),
        [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
        $pipes,
        null,
        maia_environment()
    );
    if (!is_resource($process)) {
        return ['status' => 1, 'output' => '', 'error' => 'Unable to start MAIA.'];
    }
    fclose($pipes[0]);
    $output = (string) stream_get_contents($pipes[1]);
    fclose($pipes[1]);
    $error = (string) stream_get_contents($pipes[2]);
    fclose($pipes[2]);
    return ['status' => proc_close($process), 'output' => $output, 'error' => $error];
}

/** @return list<array{name: string, sessions: list<string>}> */
function session_groups_read(): array
{
    $result = session_groups_run(['group', 'show', '--json']);
    if ($result['status'] !== 0) {
        session_groups_error(502, trim($result['error']) ?: trim($result['output']) ?: 'Unable to list session groups.');
    }
    $groups = json_decode($result['output'], true);
    if (!is_array($groups)) {
        session_groups_error(502, 'MAIA returned invalid session group data.');
    }
    return $groups;
}

function session_groups_validate_name(string $name): void
{
    if ($name === '' || $name === '.' || $name === '..' || !preg_match('/^[A-Za-z0-9_.%+-]+$/', $name)) {
        session_groups_error(400, 'Invalid group name.');
    }
}

function session_groups_run_or_error(array $arguments, string $fallback): void
{
    $result = session_groups_run($arguments);
    if ($result['status'] !== 0) {
        session_groups_error(502, trim($result['error']) ?: trim($result['output']) ?: $fallback);
    }
}

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
if ($method === 'GET') {
    $groups = session_groups_read();
    echo json_encode(['ok' => true, 'groups' => $groups], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}
if ($method !== 'POST') {
    header('Allow: GET, POST');
    session_groups_error(405, 'Method not allowed.');
}

$input = json_decode((string) (file_get_contents('php://input') ?: ''), true);
if (!is_array($input)) {
    session_groups_error(400, 'Invalid session group request.');
}
$action = (string) ($input['action'] ?? '');

if ($action === 'create' || $action === 'delete') {
    $name = trim((string) ($input['name'] ?? ''));
    session_groups_validate_name($name);
    session_groups_run_or_error(['group', $action, $name], "Unable to $action group '$name'.");
    echo json_encode(['ok' => true, 'name' => $name], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

if ($action === 'move') {
    $session = trim((string) ($input['session'] ?? ''));
    $group = trim((string) ($input['group'] ?? ''));
    if ($session === '' || !preg_match('/^[A-Za-z0-9_.%+-]+$/', $session) || $session === '_EMPTY_') {
        session_groups_error(400, 'Invalid session name.');
    }
    if (!maia_session_exists($session)) {
        session_groups_error(404, "Session '$session' does not exist.");
    }
    if ($group !== '') {
        session_groups_validate_name($group);
    }

    $groups = session_groups_read();
    $groupNames = array_map(static fn(array $item): string => (string) ($item['name'] ?? ''), $groups);
    if ($group !== '' && !in_array($group, $groupNames, true)) {
        session_groups_error(404, "Group '$group' does not exist.");
    }

    foreach ($groups as $item) {
        $name = (string) ($item['name'] ?? '');
        $members = $item['sessions'] ?? [];
        if ($name === '' || !is_array($members) || !in_array($session, $members, true)) {
            continue;
        }
        $result = session_groups_run(['group', 'remove', $name, $session]);
        if ($result['status'] !== 0) {
            session_groups_error(502, 'Unable to move session; some group memberships may already have been removed. '
                . (trim($result['error']) ?: trim($result['output']) ?: ''));
        }
    }

    if ($group !== '') {
        $result = session_groups_run(['group', 'add', $group, $session]);
        if ($result['status'] !== 0) {
            session_groups_error(502, 'Unable to add the session to its new group; it may now be ungrouped. '
                . (trim($result['error']) ?: trim($result['output']) ?: ''));
        }
    }

    echo json_encode(['ok' => true, 'session' => $session, 'group' => $group !== '' ? $group : null], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

session_groups_error(400, 'Unknown session group action.');
