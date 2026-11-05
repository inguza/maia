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
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
    header('Allow: GET');
    change_api_error(405, 'Method not allowed.');
}

$result = change_api_run(['change', 'list', '--all-states']);
if ($result['status'] !== 0) {
    change_api_error(502, trim($result['error']) ?: trim($result['output']) ?: 'Unable to list changes.');
}

echo json_encode([
    'ok' => true,
    'changes' => change_api_parse_list($result['output']),
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
