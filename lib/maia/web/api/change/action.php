<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 */

declare(strict_types=1);

require_once __DIR__ . '/common.php';

header('Content-Type: application/json; charset=utf-8');
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
    header('Allow: POST');
    change_api_error(405, 'Method not allowed.');
}

$body = json_decode((string) file_get_contents('php://input'), true);
if (!is_array($body)) {
    change_api_error(400, 'Invalid JSON body.');
}
$id = trim((string) ($body['id'] ?? ''));
$action = trim((string) ($body['action'] ?? ''));
if ($id === '' || !preg_match('/^[A-Za-z0-9_.+\-]+$/', $id)) {
    change_api_error(400, 'A valid change ID is required.');
}
$allowedActions = ['pending', 'applied', 'skipped', 'running', 'finished', 'failed', 'apply', 'revert', 'do'];
if (!in_array($action, $allowedActions, true)) {
    change_api_error(400, 'Unsupported change action.');
}

$result = change_api_run(['change', $action, $id]);
if ($result['status'] !== 0) {
    change_api_error(502, trim($result['error']) ?: trim($result['output']) ?: 'Unable to update change.');
}

echo json_encode([
    'ok' => true,
    'message' => trim($result['output']) ?: 'Change updated.',
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
