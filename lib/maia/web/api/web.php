<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */

declare(strict_types=1);

require_once __DIR__ . '/../core/common.php';
require_once __DIR__ . '/../core/auth.php';

if (session_status() !== PHP_SESSION_ACTIVE) {
    session_start();
}

function maia_validate_environment(): void
{
    $home = getenv('MAIA_HOME');
    if (!$home || !is_dir($home)) {
    header('Content-Type: text/html; charset=utf-8');
        http_response_code(500);
        echo '<h1>MAIA configuration error</h1>';
        echo '<p>MAIA_HOME is not set to a valid MAIA directory.</p>';
        exit;
    }

    $bin = getenv('MAIA_BIN');
    if (!$bin || !is_file($bin) || !is_executable($bin)) {
    header('Content-Type: text/html; charset=utf-8');
        http_response_code(500);
        echo '<h1>MAIA configuration error</h1>';
        echo '<p>MAIA_BIN is not set to an executable MAIA binary.</p>';
        exit;
    }
}

function maia_workspace_base(): ?string
{
    $home = maia_home_dir();
    if ($home === null || $home === '') {
        return null;
    }
    return dirname($home);
}

function maia_expand_home_path(string $path): string
{
    $home = maia_workspace_base();
    if ($home === null || $home === '') {
        return $path;
    }
    if ($path === '~') {
        return $home;
    }
    if (str_starts_with($path, '~/') || str_starts_with($path, '~' . DIRECTORY_SEPARATOR)) {
        return $home . DIRECTORY_SEPARATOR . ltrim(substr($path, 2), '/\\');
    }
    if ($path !== '' && $path[0] !== '/' && !preg_match('/^[A-Za-z]:[\\\\\/]/', $path)) {
        return $home . DIRECTORY_SEPARATOR . $path;
    }
    return $path;
}

function maia_path_within_home(string $path): bool
{
    $home = maia_workspace_base();
    $resolvedHome = $home === null ? false : realpath($home);
    $resolvedPath = realpath($path);
    if ($resolvedHome === false || $resolvedPath === false) {
        return false;
    }
    $prefix = rtrim($resolvedHome, DIRECTORY_SEPARATOR . '/\\') . DIRECTORY_SEPARATOR;
    return $resolvedPath === $resolvedHome || str_starts_with($resolvedPath, $prefix);
}

function maia_relative_home_path(string $path): string
{
    $home = maia_workspace_base();
    $resolvedPath = realpath($path);
    if ($home === null || $home === '' || $resolvedPath === false) {
        return $path;
    }
    $resolvedHome = realpath($home);
    if ($resolvedHome === false) {
        return $path;
    }

    $baseParts = explode('/', trim(str_replace('\\', '/', $resolvedHome), '/'));
    $pathParts = explode('/', trim(str_replace('\\', '/', $resolvedPath), '/'));
    $common = 0;
    while (isset($baseParts[$common], $pathParts[$common]) &&
           $baseParts[$common] === $pathParts[$common]) {
        $common++;
    }
    $relative = array_merge(
        array_fill(0, count($baseParts) - $common, '..'),
        array_slice($pathParts, $common)
    );
    return $relative === [] ? '.' : implode('/', $relative);
}

function maia_session_exists(string $name): bool
{
    if (!preg_match('/^[A-Za-z0-9_.%+-]+$/', $name) || $name === '_EMPTY_') {
        return false;
    }

    $process = proc_open(
        [maia_binary(), 'session', 'exist', $name],
        [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
        $pipes,
        null,
        maia_environment()
    );
    if (!is_resource($process)) {
        return false;
    }
    fclose($pipes[0]);
    stream_get_contents($pipes[1]);
    fclose($pipes[1]);
    stream_get_contents($pipes[2]);
    fclose($pipes[2]);
    return proc_close($process) === 0;
}

function maia_ensure_session(string $name): bool
{
    if (!preg_match('/^[A-Za-z0-9_.%+\\-]+$/', $name) || $name === '_EMPTY_') {
        return false;
    }

    $environment = maia_environment();
    $descriptors = [
        0 => ['pipe', 'r'],
        1 => ['pipe', 'w'],
        2 => ['pipe', 'w'],
    ];
    $run = static function (array $arguments) use ($descriptors, $environment): int {
        $process = proc_open(
            array_merge([maia_binary()], $arguments),
            $descriptors,
            $pipes,
            null,
            $environment
        );
        if (!is_resource($process)) {
            return 1;
        }
        fclose($pipes[0]);
        stream_get_contents($pipes[1]);
        fclose($pipes[1]);
        stream_get_contents($pipes[2]);
        fclose($pipes[2]);
        return proc_close($process);
    };

    if ($run(['session', 'exist', $name]) === 0) {
        return true;
    }

    return $run(['session', 'create', $name]) === 0;
}

/** @return array<int, string> */
function maia_sessions(): array
{
    $descriptors = [
        0 => ['pipe', 'r'],
        1 => ['pipe', 'w'],
        2 => ['pipe', 'w'],
    ];

    $process = proc_open(
        [maia_binary(), 'session', 'list'],
        $descriptors,
        $pipes,
        null,
        maia_environment()
    );

    if (!is_resource($process)) {
        return [];
    }

    fclose($pipes[0]);
    $output = stream_get_contents($pipes[1]);
    fclose($pipes[1]);
    fclose($pipes[2]);
    proc_close($process);

    $sessions = [];
    foreach (preg_split('/\R/', (string) $output) as $line) {
        if (preg_match('/^\s*[* ]\s+(\S+)/', $line, $matches)) {
            $name = $matches[1];
            $name = preg_replace('/\(defunct\)$/', '', $name) ?? $name;
            $sessions[$name] = true;
        }
    }

    return array_keys($sessions);
}

function maia_session_workspace(string $session): ?string
{
    if (!preg_match('/^[A-Za-z0-9_.%+\\-]+$/', $session) || $session === '_EMPTY_') {
        return null;
    }
    $process = proc_open(
        [maia_binary(), 'session', 'show', '--raw', $session],
        [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
        $pipes,
        null,
        maia_environment()
    );
    if (!is_resource($process)) {
        return null;
    }
    fclose($pipes[0]);
    $output = (string) stream_get_contents($pipes[1]);
    fclose($pipes[1]);
    fclose($pipes[2]);
    if (proc_close($process) !== 0) {
        return null;
    }
    foreach (preg_split('/\\R/', $output) as $line) {
        if (preg_match('/^workspace:\\s*(.*)$/', $line, $match)) {
            $workspace = trim($match[1]);
            return preg_match('/^[A-Za-z0-9_.%+\\-]+$/', $workspace) ? $workspace : null;
        }
    }
    return null;
}

function maia_selected_session(): ?string
{
    $headerSession = trim((string) ($_SERVER['HTTP_X_MAIA_SESSION'] ?? ''));
    if ($headerSession !== '') {
        return $headerSession;
    }

    $urlSession = trim((string) ($_SERVER['MAIA_URL_SESSION'] ?? ''));
    if ($urlSession !== '') {
        return $urlSession;
    }

    // Compatibility fallback for older clients that still use PHP sessions.
    $selected = trim((string) ($_SESSION['maia_session'] ?? ''));
    if ($selected !== '') {
        return $selected;
    }

    $environmentSession = trim((string) (getenv('MAIA_SESSION') ?: ''));
    return $environmentSession !== '' ? $environmentSession : null;
}

/** @return array<string, string> */
function maia_environment(): array
{
    $environment = getenv();
    $profile = trim((string) ($_SERVER['HTTP_X_MAIA_PROFILE'] ?? ''));
    if ($profile === '') {
        $profile = trim((string) ($_SERVER['MAIA_URL_PROFILE'] ?? ''));
    }
    $workspace = trim((string) ($_SERVER['HTTP_X_MAIA_WORKSPACE'] ?? ''));
    $urlWorkspace = trim((string) ($_SERVER['MAIA_URL_WORKSPACE'] ?? ''));
    $homePage = trim((string) ($_SERVER['HTTP_X_MAIA_HOME'] ?? $_SERVER['MAIA_URL_HOME'] ?? ''));
    if ($workspace === '') {
        $workspace = $urlWorkspace;
    }

    if ($profile !== '') {
        // Profile pages are independent of the currently selected session.
        // Use the reserved null session so legacy resolution code has a
        // deterministic session context without creating a real session.
        $environment['MAIA_SESSION'] = '_EMPTY_';
        $environment['MAIA_PROFILE'] = $profile;
    } elseif ($urlWorkspace !== '') {
        // Workspace pages are also independent of the currently selected
        // session. The explicit workspace selects the context being edited.
        $environment['MAIA_SESSION'] = '_EMPTY_';
        unset($environment['MAIA_PROFILE']);
    } elseif ($homePage !== '') {
        // The home page is an independent scope and must not inherit the
        // currently selected session, workspace, or profile.
        $environment['MAIA_SESSION'] = '_EMPTY_';
        unset($environment['MAIA_PROFILE']);
    } else {
        $session = maia_selected_session();
        if ($session === null || $session === '') {
            unset($environment['MAIA_SESSION']);
        } else {
            $environment['MAIA_SESSION'] = $session;
        }
        unset($environment['MAIA_PROFILE']);
    }

    if ($workspace !== '') {
        $environment['MAIA_WORKSPACE'] = $workspace;
    } elseif ($profile !== '' || $homePage !== '') {
        // Do not let a workspace inherited from the PHP process or another
        // request affect profile or home resolution.
        unset($environment['MAIA_WORKSPACE']);
    }

    // Do not hold the PHP session lock while MAIA performs a long-running
    // operation such as send or history retrieval.
    if (session_status() === PHP_SESSION_ACTIVE) {
        session_write_close();
    }

    return $environment;
}

function maia_initial_session(): ?string
{
    $urlSession = trim((string) ($_SERVER['MAIA_URL_SESSION'] ?? ''));
    if ($urlSession !== '') {
        return $urlSession;
    }

    $selected = trim((string) ($_SESSION['maia_session'] ?? ''));
    if ($selected !== '') {
        return $selected;
    }

    $environmentSession = trim((string) (getenv('MAIA_SESSION') ?: ''));
    if ($environmentSession !== '') {
        return $environmentSession;
    }

    $process = proc_open(
        [maia_binary(), '--query', 'session'],
        [
            0 => ['pipe', 'r'],
            1 => ['pipe', 'w'],
            2 => ['pipe', 'w'],
        ],
        $pipes
    );

    if (!is_resource($process)) {
        return null;
    }

    fclose($pipes[0]);
    $session = trim((string) stream_get_contents($pipes[1]));
    fclose($pipes[1]);
    fclose($pipes[2]);
    proc_close($process);

    // --query session marks a missing metadata file with a trailing '!'.
    return rtrim($session, '!') ?: null;
}


// Every API endpoint uses the same explicit authentication cookie. The
// bootstrap page is handled by index.php and is intentionally not gated here.
$maiaWebRequestPath = maia_request_path();
if (str_starts_with($maiaWebRequestPath, '/api/')) {
    maia_require_auth();
}

/** @return list<array{text: string, path: string|null, session: string|null}> */
function maia_history_text_parts(string $text, ?string $workspaceRoot, ?string $sessionName = null): array
{
    $pattern = '/[A-Za-z0-9_-]+(?:[.\\/][A-Za-z0-9_-]+)+/';
    if ($workspaceRoot === null || $workspaceRoot === '' ||
        preg_match_all($pattern, $text, $matches, PREG_OFFSET_CAPTURE) === false ||
        empty($matches[0])) {
        return [['text' => $text, 'path' => null, 'session' => null]];
    }

    $parts = [];
    $offset = 0;
    $prefix = rtrim($workspaceRoot, DIRECTORY_SEPARATOR . '/\\') . DIRECTORY_SEPARATOR;
    foreach ($matches[0] as [$candidate, $byteOffset]) {
        // Do not split the host/path portion out of an HTTP(S) URL. The
        // session-history renderer handles URLs separately in JavaScript.
        if ($byteOffset >= 3 && substr($text, $byteOffset - 3, 3) === '://') {
            continue;
        }
        $candidateLength = strlen($candidate);
        if ($byteOffset > $offset) {
            $parts[] = ['text' => substr($text, $offset, $byteOffset - $offset), 'path' => null, 'session' => null];
        }
        $resolved = false;
        if ($candidate !== '' && !str_contains($candidate, "\0") &&
            !str_contains($candidate, '..')) {
            $candidatePath = realpath($workspaceRoot . DIRECTORY_SEPARATOR .
                str_replace(['/', '\\'], DIRECTORY_SEPARATOR, $candidate));
            if ($candidatePath !== false &&
                ($candidatePath === $workspaceRoot || str_starts_with($candidatePath, $prefix))) {
                $resolved = trim(str_replace('\\', '/', substr($candidatePath, strlen($workspaceRoot))), '/');
            }
        }
        $parts[] = [
            'text' => $candidate,
            'path' => $resolved === false ? null : $resolved,
            'session' => $resolved === false ? null : $sessionName,
        ];
        $offset = $byteOffset + $candidateLength;
    }
    if ($offset < strlen($text)) {
        $parts[] = ['text' => substr($text, $offset), 'path' => null, 'session' => null];
    }
    return $parts;
}

function maia_history_workspace_root(): ?string
{
    $workspace = trim((string) (getenv('MAIA_WORKSPACE') ?: ''));
    if ($workspace === '') {
        $session = maia_selected_session();
        $workspace = $session === null ? '' : (maia_session_workspace($session) ?: '');
    }
    if ($workspace === '') {
        return null;
    }
    $home = maia_home_dir();
    if ($home === null || $home === '') {
        return null;
    }
    $metadata = $home . DIRECTORY_SEPARATOR . 'workspaces' . DIRECTORY_SEPARATOR .
        $workspace . DIRECTORY_SEPARATOR . 'workspace.myl';
    if (!is_file($metadata)) {
        return null;
    }
    $root = '';
    foreach (file($metadata, FILE_IGNORE_NEW_LINES) ?: [] as $line) {
        if (preg_match('/^path:\\s*(.*)$/', $line, $match)) {
            $root = trim($match[1]);
            break;
        }
    }
    if ($root !== '' && $root[0] !== '/' && !preg_match('/^[A-Za-z]:[\\\\\\/]/', $root)) {
        $root = $home . DIRECTORY_SEPARATOR . $root;
    }
    $root = realpath($root);
    return $root !== false && is_dir($root) ? $root : null;
}

function maia_annotate_history_response(string $output): string
{
    $response = json_decode($output, true);
    if (!is_array($response) || !is_array($response['items'] ?? null)) {
        return $output;
    }
    $root = maia_history_workspace_root();
    $sessionName = maia_selected_session();
    foreach ($response['items'] as &$item) {
        if (is_array($item) && ($item['hidden'] ?? false) !== true &&
            ($item['hidden'] ?? 0) !== 1 && ($item['hidden'] ?? '') !== 'true') {
            if (array_key_exists('content', $item) && is_string($item['content'])) {
                $item['contentParts'] = maia_history_text_parts($item['content'], $root, $sessionName);
            }
            if (is_array($item['backup'] ?? null) &&
                is_string($item['backup']['content'] ?? null)) {
                $item['backup']['contentParts'] = maia_history_text_parts($item['backup']['content'], $root, $sessionName);
            }
        }
    }
    unset($item);
    return json_encode($response, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
}

if ($maiaWebRequestPath === '/api/history/show') {
    ob_start('maia_annotate_history_response');
}
