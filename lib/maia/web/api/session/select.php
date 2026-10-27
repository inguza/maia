<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola.com>
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

// The browser selected this name from its already-loaded session list. Store it
// immediately; history loading will report if the session no longer exists.
if (session_status() !== PHP_SESSION_ACTIVE) {
    session_start();
}
$_SESSION['maia_session'] = $name;
session_write_close();

echo json_encode([
    'ok' => true,
    'selected' => $name,
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
