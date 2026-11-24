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

$sessions = maia_sessions();
$home = maia_home_dir();
$items = [];
foreach ($sessions as $name) {
    $workspace = '';
    if ($home !== null && $home !== '') {
        $metadata = $home . DIRECTORY_SEPARATOR . 'sessions' . DIRECTORY_SEPARATOR
            . $name . DIRECTORY_SEPARATOR . 'session.myl';
        $workspace = myl_get($metadata, 'workspace') ?? '';
    }
    // Sessions tied to a workspace the GUI policy disallows are omitted from
    // the API response, not merely hidden in the sidebar.
    if ($workspace !== '' && !maia_workspace_is_usable($workspace)) {
        continue;
    }
    $items[] = ['name' => $name, 'workspace' => $workspace];
}
$visibleNames = array_column($items, 'name');
$preferred = $headerSelected !== ''
    ? $headerSelected
    : (in_array($cookieSelected, $sessions, true)
        ? $cookieSelected
        : (in_array($environmentSession, $sessions, true) ? $environmentSession : ($environmentSession ?: null)));
$selected = is_string($preferred) && in_array($preferred, $visibleNames, true) ? $preferred : null;
foreach ($items as &$item) {
    $item['selected'] = $item['name'] === $selected;
}
unset($item);

echo json_encode([
    'ok' => true,
    'selected' => $selected,
    'sessions' => $items,
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
