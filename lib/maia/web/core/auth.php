<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */

function maia_auth_file(): ?string
{
    $home = maia_home_dir();
    return $home === null ? null : $home . DIRECTORY_SEPARATOR . 'auth.myl';
}

/** @return list<array{name: string, salt: string, hash: string}> */
function maia_auth_tokens(): array
{
    $file = maia_auth_file();
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

function maia_auth_cookie_value(): string
{
    return rawurldecode((string) ($_COOKIE['MAIA_GUI_AUTH'] ?? ''));
}

function maia_auth_cookie_valid(): bool
{
    $cookie = maia_auth_cookie_value();
    if (!preg_match('/^([0-9a-f]+):([0-9a-f]+)$/', $cookie, $match)) {
        return false;
    }

    $salt = $match[1];
    $secret = $match[2];
    $hash = hash('sha256', $salt . ':' . $secret);
    foreach (maia_auth_tokens() as $token) {
        if ($token['salt'] === $salt && hash_equals($token['hash'], $hash)) {
            return true;
        }
    }
    return false;
}

function maia_refresh_auth_cookie(): void
{
    $options = [
        'expires' => time() + 365 * 24 * 60 * 60,
        'path' => maia_base_path() . '/' ?: '/',
        'secure' => (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off'),
        'httponly' => true,
        'samesite' => 'Lax',
    ];
    setcookie('MAIA_GUI_AUTH', maia_auth_cookie_value(), $options);
}

function maia_auth_bootstrap(): never
{
    $cookiePath = maia_base_path() . '/' ?: '/';
    $cookiePathJson = json_encode($cookiePath, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
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
    const cookiePath = {$cookiePathJson};
    document.cookie = 'MAIA_GUI_AUTH=' + value + '; Path=' + cookiePath + '; SameSite=Lax';
    message.textContent = 'Authentication token received. Reloading...';
    history.replaceState({}, '', location.pathname + location.search);
    location.reload();
})();
</script></body></html>
HTML;
    exit;
}

function maia_require_auth(): void
{
    if (!maia_auth_cookie_valid()) {
        maia_auth_bootstrap();
    }
    maia_refresh_auth_cookie();
}

function maia_authenticate_page(): bool
{
    if (!maia_auth_cookie_valid()) {
        maia_auth_bootstrap();
    }
    maia_refresh_auth_cookie();
    return true;
}
