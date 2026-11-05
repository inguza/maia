<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 * Licensed under the GNU General Public License v3.0.
 */

declare(strict_types=1);

require_once __DIR__ . '/common.php';

header('Content-Type: application/json; charset=utf-8');
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
    header('Allow: GET');
    change_api_error(405, 'Method not allowed.');
}

$id = trim((string) ($_GET['id'] ?? ''));
if ($id === '' || !preg_match('/^[A-Za-z0-9_.+\\-]+$/', $id)) {
    change_api_error(400, 'A valid change ID is required.');
}

$result = change_api_run(['change', 'show', $id]);
if ($result['status'] !== 0) {
    change_api_error(502, trim($result['error']) ?: trim($result['output']) ?: 'Unable to show change.');
}
$change = change_api_parse_show_metadata($id, $result['output']);
if ($change === null) {
    change_api_error(404, 'Change metadata was not found.');
}

echo json_encode([
    'ok' => true,
    'id' => $id,
    'change' => $change,
    'detail' => $result['output'],
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
