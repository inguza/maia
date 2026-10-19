<?php

declare(strict_types=1);

if (session_status() !== PHP_SESSION_ACTIVE) {
    session_start();
}

function maia_web_binary(): string
{
    return getenv('MAIA_BIN') ?: 'maia';
}

function maia_web_auth_file(): ?string
{
    $home = maia_web_home_dir();
    return $home === null ? null : $home . DIRECTORY_SEPARATOR . 'auth.myl';
}

/** @return list<array{name: string, salt: string, hash: string}> */
function maia_web_auth_tokens(): array
{
    $file = maia_web_auth_file();
    if ($file === null || !is_file($file)) {
        return [];
    }

    $tokens = [];
    $inTokens = false;
    $addToken = static function (string $value) use (&$tokens): void {
        if (preg_match('/^(?:  )?([A-Za-z0-9_-]+):([0-9a-f]+):([0-9a-f]{64})$/', trim($value), $match)) {
            $tokens[] = ['name' => $match[1], 'salt' => $match[2], 'hash' => $match[3]];
        }
    };
    foreach (file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
        if (preg_match('/^tokens:\s*(.*)$/', $line, $match)) {
            $inTokens = true;
            if ($match[1] !== '') {
                $addToken($match[1]);
            }
            continue;
        }
        if (!$inTokens) {
            continue;
        }
        if (preg_match('/^\s{2}(.+)$/', $line, $match)) {
            $addToken($match[1]);
            continue;
        }
        $inTokens = false;
    }
    return $tokens;
}

function maia_web_auth_cookie_value(): string
{
    return rawurldecode((string) ($_COOKIE['MAIA_GUI_AUTH'] ?? ''));
}

function maia_web_auth_cookie_valid(): bool
{
    $cookie = maia_web_auth_cookie_value();
    if (!preg_match('/^([0-9a-f]+):([0-9a-f]+)$/', $cookie, $match)) {
        return false;
    }

    $salt = $match[1];
    $secret = $match[2];
    $hash = hash('sha256', $salt . ':' . $secret);
    foreach (maia_web_auth_tokens() as $token) {
        if ($token['salt'] === $salt && hash_equals($token['hash'], $hash)) {
            return true;
        }
    }
    return false;
}

function maia_web_refresh_auth_cookie(): void
{
    $options = [
        'expires' => time() + 365 * 24 * 60 * 60,
        'path' => '/',
        'secure' => (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off'),
        'httponly' => true,
        'samesite' => 'Lax',
    ];
    setcookie('MAIA_GUI_AUTH', maia_web_auth_cookie_value(), $options);
}

function maia_web_auth_bootstrap(): never
{
    header('Content-Type: text/html; charset=utf-8');
    http_response_code(401);
    echo <<<HTML
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>MAIA authentication</title></head>
<body><main><h1>MAIA authentication required</h1><p id="message">Checking authentication link...</p></main>
<script>
(() => {
    const message = document.getElementById('message');
    const value = new URLSearchParams(location.hash.slice(1)).get('auth');
    if (!value || !/^[0-9a-f]+:[0-9a-f]+$/.test(value)) {
        message.innerHTML = 'Authentication failed. Run "<code>maia gui create</code>" and use the generated authentication URL.';
        return;
    }
    document.cookie = 'MAIA_GUI_AUTH=' + value + '; Path=/; SameSite=Lax';
    message.textContent = 'Authentication token received. Reloading...';
    history.replaceState({}, '', location.pathname + location.search);
    location.reload();
})();
</script></body></html>
HTML;
    exit;
}

function maia_web_require_auth(): void
{
    if (!maia_web_auth_cookie_valid()) {
        maia_web_auth_bootstrap();
    }
    maia_web_refresh_auth_cookie();
}

function maia_web_authenticate_page(): bool
{
    if (!maia_web_auth_cookie_valid()) {
        maia_web_auth_bootstrap();
    }
    maia_web_refresh_auth_cookie();
    return true;
}

function maia_web_home_dir(): ?string
{
    $process = proc_open(
        [maia_web_binary(), 'home', 'show'],
        [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
        $pipes,
        null,
        maia_web_environment()
    );
    if (!is_resource($process)) {
        return null;
    }
    fclose($pipes[0]);
    $output = trim((string) stream_get_contents($pipes[1]));
    fclose($pipes[1]);
    fclose($pipes[2]);
    $status = proc_close($process);
    if ($status !== 0 || $output === '') {
        return null;
    }
    return rtrim($output, DIRECTORY_SEPARATOR . '/\\');
}

function maia_web_workspace_base(): ?string
{
    $home = maia_web_home_dir();
    if ($home === null || $home === '') {
        return null;
    }
    return dirname($home);
}

function maia_web_expand_home_path(string $path): string
{
    $home = maia_web_workspace_base();
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

function maia_web_path_within_home(string $path): bool
{
    $home = maia_web_workspace_base();
    $resolvedHome = $home === null ? false : realpath($home);
    $resolvedPath = realpath($path);
    if ($resolvedHome === false || $resolvedPath === false) {
        return false;
    }
    $prefix = rtrim($resolvedHome, DIRECTORY_SEPARATOR . '/\\') . DIRECTORY_SEPARATOR;
    return $resolvedPath === $resolvedHome || str_starts_with($resolvedPath, $prefix);
}

function maia_web_relative_home_path(string $path): string
{
    $home = maia_web_workspace_base();
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

/** @return array<int, string> */
function maia_web_sessions(): array
{
    $descriptors = [
        0 => ['pipe', 'r'],
        1 => ['pipe', 'w'],
        2 => ['pipe', 'w'],
    ];

    $process = proc_open(
        [maia_web_binary(), 'session', 'list'],
        $descriptors,
        $pipes
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

function maia_web_selected_session(): ?string
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
function maia_web_environment(): array
{
    $environment = getenv();
    $session = maia_web_selected_session();

    if ($session === null || $session === '') {
        unset($environment['MAIA_SESSION']);
    } else {
        $environment['MAIA_SESSION'] = $session;
    }

    // Do not hold the PHP session lock while MAIA performs a long-running
    // operation such as send or history retrieval.
    if (session_status() === PHP_SESSION_ACTIVE) {
        session_write_close();
    }

    return $environment;
}

function maia_web_initial_session(): ?string
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
        [maia_web_binary(), '--query', 'session'],
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
$maiaWebRequestPath = parse_url($_SERVER['REQUEST_URI'] ?? '', PHP_URL_PATH);
if (is_string($maiaWebRequestPath) && str_starts_with($maiaWebRequestPath, '/api/')) {
    maia_web_require_auth();
}
