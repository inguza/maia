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

header('Content-Type: application/json; charset=utf-8');

function session_select_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode([
        'ok' => false,
        'error' => $message,
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: POST');
    session_select_error(405, 'Method not allowed.');
}

$name = trim((string) (file_get_contents('php://input') ?: ''));
if ($name === '' || !preg_match('/^[A-Za-z0-9_.%+-]+$/', $name)) {
    session_select_error(400, 'Invalid session name.');
}

// The browser normally selects from the filtered list; keep direct requests
// from selecting a session whose workspace is unavailable to the web UI.
$workspace = maia_session_workspace($name) ?? '';
if ($workspace !== '' && !maia_workspace_is_usable($workspace)) {
    session_select_error(404, 'Session is not available to the web interface.');
}
if (session_status() !== PHP_SESSION_ACTIVE) {
    session_start();
}
$_SESSION['maia_session'] = $name;
session_write_close();

echo json_encode([
    'ok' => true,
    'selected' => $name,
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
