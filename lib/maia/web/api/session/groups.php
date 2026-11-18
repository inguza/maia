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
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Pragma: no-cache');

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

/** Resolve the same home directory used by MAIA's group commands. */
function session_groups_directory(): string
{
    static $directory = null;
    if ($directory !== null) {
        return $directory;
    }

    $result = session_groups_run(['home', 'show']);
    if ($result['status'] !== 0) {
        session_groups_error(502, trim($result['error']) ?: trim($result['output']) ?: 'Unable to locate session group data.');
    }
    $home = trim($result['output']);
    if ($home === '') {
        session_groups_error(500, 'MAIA did not return a home directory.');
    }
    $directory = rtrim($home, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR . 'groups' . DIRECTORY_SEPARATOR . 'session';
    return $directory;
}

/** Acquire the shared lock so concurrent web requests cannot interleave group updates. */
function session_groups_lock(int $mode)
{
    $directory = session_groups_directory();
    if (!is_dir($directory) && !mkdir($directory, 0770, true) && !is_dir($directory)) {
        session_groups_error(500, 'Unable to access the session groups directory.');
    }
    $handle = @fopen($directory . DIRECTORY_SEPARATOR . '.groups.lock', 'c');
    if ($handle === false || !flock($handle, $mode)) {
        if (is_resource($handle)) {
            fclose($handle);
        }
        session_groups_error(500, 'Unable to lock session group data.');
    }
    return $handle;
}

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
if ($method === 'GET') {
    $lock = session_groups_lock(LOCK_SH);
    $groups = session_groups_read();
    flock($lock, LOCK_UN);
    fclose($lock);
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
$lock = session_groups_lock(LOCK_EX);

if ($action === 'create' || $action === 'delete') {
    $name = trim((string) ($input['name'] ?? ''));
    session_groups_validate_name($name);
    session_groups_run_or_error(['group', $action, $name], "Unable to $action group '$name'.");
    echo json_encode(['ok' => true, 'name' => $name], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

if ($action === 'rename') {
    $oldName = trim((string) ($input['oldName'] ?? ''));
    $newName = trim((string) ($input['newName'] ?? ''));
    session_groups_validate_name($oldName);
    session_groups_validate_name($newName);
    if ($oldName === $newName) {
        echo json_encode(['ok' => true, 'name' => $newName], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
        exit;
    }

    $groups = session_groups_read();
    $oldNames = [];
    $renames = [];
    foreach ($groups as $item) {
        $groupName = (string) ($item['name'] ?? '');
        if ($groupName === $oldName || strncmp($groupName, $oldName . '%', strlen($oldName) + 1) === 0) {
            $oldNames[$groupName] = true;
            $renames[$groupName] = $newName . substr($groupName, strlen($oldName));
        }
    }
    if (!isset($oldNames[$oldName])) {
        session_groups_error(404, "Group '$oldName' does not exist.");
    }
    foreach ($renames as $targetName) {
        session_groups_validate_name($targetName);
        if (in_array($targetName, array_column($groups, 'name'), true) && !isset($oldNames[$targetName])) {
            session_groups_error(409, "Group '$targetName' already exists.");
        }
    }

    $directory = session_groups_directory();
    $staged = [];
    foreach ($renames as $sourceName => $targetName) {
        $sourcePath = $directory . DIRECTORY_SEPARATOR . $sourceName . '.txt';
        if (!is_file($sourcePath)) {
            foreach ($staged as $temporaryPath) @unlink($temporaryPath);
            session_groups_error(404, "Group '$sourceName' does not exist.");
        }
        $temporaryPath = @tempnam($directory, '.group-rename-');
        $contents = @file_get_contents($sourcePath);
        if ($temporaryPath === false || $contents === false || @file_put_contents($temporaryPath, $contents) === false) {
            if (is_string($temporaryPath)) @unlink($temporaryPath);
            foreach ($staged as $path) @unlink($path);
            session_groups_error(500, 'Unable to stage group rename.');
        }
        @chmod($temporaryPath, fileperms($sourcePath) & 0777);
        $staged[$sourceName] = $temporaryPath;
    }

    $backups = [];
    foreach (array_keys($renames) as $sourceName) {
        $sourcePath = $directory . DIRECTORY_SEPARATOR . $sourceName . '.txt';
        $backupPath = $sourcePath . '.rename-' . bin2hex(random_bytes(6));
        if (!@rename($sourcePath, $backupPath)) {
            foreach ($backups as $originalName => $path) {
                @rename($path, $directory . DIRECTORY_SEPARATOR . $originalName . '.txt');
            }
            foreach ($staged as $path) @unlink($path);
            session_groups_error(500, 'Unable to prepare group rename.');
        }
        $backups[$sourceName] = $backupPath;
    }

    $createdTargets = [];
    foreach ($renames as $sourceName => $targetName) {
        $targetPath = $directory . DIRECTORY_SEPARATOR . $targetName . '.txt';
        if (!@rename($staged[$sourceName], $targetPath)) {
            foreach ($createdTargets as $path) @unlink($path);
            foreach ($backups as $originalName => $path) {
                @rename($path, $directory . DIRECTORY_SEPARATOR . $originalName . '.txt');
            }
            foreach ($staged as $path) @unlink($path);
            session_groups_error(500, 'Unable to complete group rename.');
        }
        $createdTargets[] = $targetPath;
    }
    foreach ($backups as $path) @unlink($path);

    echo json_encode(['ok' => true, 'name' => $newName], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
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

    // Add to the destination first, so a failure cannot leave the session ungrouped.
    if ($group !== '') {
        $result = session_groups_run(['group', 'add', $group, $session]);
        if ($result['status'] !== 0) {
            session_groups_error(502, 'Unable to add the session to its new group; its existing memberships were left unchanged. '
                . (trim($result['error']) ?: trim($result['output']) ?: ''));
        }
    }

    foreach ($groups as $item) {
        $name = (string) ($item['name'] ?? '');
        $members = $item['sessions'] ?? [];
        if ($name === '' || $name === $group || !is_array($members) || !in_array($session, $members, true)) {
            continue;
        }
        $result = session_groups_run(['group', 'remove', $name, $session]);
        if ($result['status'] !== 0) {
            session_groups_error(502, 'Unable to remove the session from all previous groups; it has been added to its new group. '
                . (trim($result['error']) ?: trim($result['output']) ?: ''));
        }
    }

    $updatedGroups = session_groups_read();
    $membershipCorrect = static function (array $currentGroups) use ($session, $group): bool {
        foreach ($currentGroups as $item) {
            $name = (string) ($item['name'] ?? '');
            $members = $item['sessions'] ?? [];
            $shouldContain = $group !== '' && $name === $group;
            if (is_array($members) && in_array($session, $members, true) !== $shouldContain) {
                return false;
            }
        }
        return true;
    };

    if (!$membershipCorrect($updatedGroups)) {
        // Repair a transient write race before reporting success to the sidebar.
        if ($group !== '') {
            session_groups_run_or_error(['group', 'add', $group, $session], 'Unable to persist the new session group.');
        }
        foreach ($updatedGroups as $item) {
            $name = (string) ($item['name'] ?? '');
            $members = $item['sessions'] ?? [];
            if ($name === '' || $name === $group || !is_array($members) || !in_array($session, $members, true)) {
                continue;
            }
            session_groups_run_or_error(['group', 'remove', $name, $session], 'Unable to remove an old session group.');
        }
        $updatedGroups = session_groups_read();
        if (!$membershipCorrect($updatedGroups)) {
            session_groups_error(502, 'The session group update did not persist as requested.');
        }
    }

    echo json_encode(['ok' => true, 'session' => $session, 'group' => $group !== '' ? $group : null], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

session_groups_error(400, 'Unknown session group action.');
