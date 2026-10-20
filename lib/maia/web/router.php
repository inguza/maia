<?php

declare(strict_types=1);

$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);

if ($path === '/status') {
    header('Content-Type: text/plain; charset=utf-8');
    echo "OK\n";
    return true;
}

// Authenticate the root request before redirecting it to the canonical
// session URL. This prevents an unauthenticated client from being redirected
// before the authentication bootstrap has run.
if ($path === '/' || $path === '') {
    require_once __DIR__ . '/api/web.php';
    maia_web_authenticate_page();

    $session = trim((string) (getenv('MAIA_SESSION') ?: 'default'));
    header('Location: /session/' . rawurlencode($session), true, 302);
    exit;
}

if (preg_match('#^/session/(.+)$#', $path, $matches)) {
    $session = rawurldecode($matches[1]);
    if ($session === '' || !preg_match('/^[A-Za-z0-9_.%+-]+$/', $session)) {
        http_response_code(404);
        echo "Session not found.\n";
        return true;
    }
    $_SERVER['MAIA_URL_SESSION'] = $session;
    require __DIR__ . '/index.php';
    return true;
}

if (preg_match('#^/workspace/(.+)$#', $path, $matches)) {
    $workspace = rawurldecode($matches[1]);
    if ($workspace === '' || !preg_match('/^[A-Za-z0-9_.%+\-]+$/', $workspace)) {
        http_response_code(404);
        echo "Workspace not found.\n";
        return true;
    }
    $_SERVER['MAIA_URL_WORKSPACE'] = $workspace;
    require __DIR__ . '/index.php';
    return true;
}

if (preg_match('#^/profile/(.+)$#', $path, $matches)) {
    $profile = rawurldecode($matches[1]);
    if ($profile === '' || !preg_match('/^[A-Za-z0-9_.%+\\-]+$/', $profile)) {
        http_response_code(404);
        echo "Profile not found.\n";
        return true;
    }
    $_SERVER['MAIA_URL_PROFILE'] = $profile;
    require __DIR__ . '/index.php';
    return true;
}

if ($path === '/home') {
    $_SERVER['MAIA_URL_HOME'] = 'home';
    require __DIR__ . '/index.php';
    return true;
}

if ($path === '/qr') {
    require __DIR__ . '/qr.php';
    return true;
}

$routes = [
    '/api/send' => __DIR__ . '/api/send.php',
    '/api/history/show' => __DIR__ . '/api/history/show.php',
    '/api/session/list' => __DIR__ . '/api/session/list.php',
    '/api/session/select' => __DIR__ . '/api/session/select.php',
    '/api/session/delete' => __DIR__ . '/api/session/delete.php',
    '/api/session/create' => __DIR__ . '/api/session/create.php',
    '/api/session/settings' => __DIR__ . '/api/session/settings.php',
    '/api/workspace/create' => __DIR__ . '/api/workspace/create.php',
    '/api/workspace/delete' => __DIR__ . '/api/workspace/delete.php',
    '/api/workspace/settings' => __DIR__ . '/api/workspace/settings.php',
    '/api/workspace/complete' => __DIR__ . '/api/workspace/complete.php',
    '/api/profile/create' => __DIR__ . '/api/profile/create.php',
    '/api/profile/delete' => __DIR__ . '/api/profile/delete.php',
    '/api/profile/settings' => __DIR__ . '/api/profile/settings.php',
    '/api/file/list' => __DIR__ . '/api/file/list.php',
    '/api/file/add' => __DIR__ . '/api/file/add.php',
    '/api/file/complete' => __DIR__ . '/api/file/complete.php',
    '/api/file/forget' => __DIR__ . '/api/file/forget.php',
    '/api/tool/context' => __DIR__ . '/api/tool/context.php',
    '/api/tool/append' => __DIR__ . '/api/tool/append.php',
    '/api/tool/disable' => __DIR__ . '/api/tool/disable.php',
    '/api/tool/clear' => __DIR__ . '/api/tool/clear.php',
    '/api/tool/delete' => __DIR__ . '/api/tool/delete.php',
    '/api/skill/context' => __DIR__ . '/api/skill/context.php',
];

if (isset($routes[$path])) {
    require $routes[$path];
    return true;
}

// Let PHP's built-in server handle existing static files and PHP files.
$file = __DIR__ . $path;
if (is_file($file)) {
    return false;
}

http_response_code(404);
header('Content-Type: text/plain; charset=utf-8');
echo "Not found.\n";
return true;
