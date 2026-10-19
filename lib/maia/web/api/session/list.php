<?php

declare(strict_types=1);

require_once __DIR__ . '/../web.php';

header('Content-Type: application/json; charset=utf-8');

function session_list_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode([
        'ok' => false,
        'error' => $message,
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    header('Allow: GET');
    session_list_error(405, 'Method not allowed.');
}

$headerSelected = trim((string) ($_SERVER['HTTP_X_MAIA_SESSION'] ?? ''));
$cookieSelected = trim((string) ($_SESSION['maia_session'] ?? ''));
$environmentSession = trim((string) (getenv('MAIA_SESSION') ?: ''));

// Listing sessions can take time. The list endpoint does not need to retain
// the PHP session lock while the CLI is running.
if (session_status() === PHP_SESSION_ACTIVE) {
    session_write_close();
}

$sessions = maia_web_sessions();
$selected = $headerSelected !== ''
    ? $headerSelected
    : (in_array($cookieSelected, $sessions, true)
        ? $cookieSelected
        : (in_array($environmentSession, $sessions, true) ? $environmentSession : ($environmentSession ?: null)));

$items = array_map(
    static fn (string $name): array => [
        'name' => $name,
        'selected' => $name === $selected,
    ],
    $sessions
);

echo json_encode([
    'ok' => true,
    'selected' => $selected,
    'sessions' => $items,
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
