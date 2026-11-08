<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 */

declare(strict_types=1);

require_once __DIR__ . '/common.php';

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
    header('Allow: GET');
    approval_api_error(405, 'Method not allowed.');
}

$targetScope = approval_api_scope();
$rulesResult = approval_api_run(['approve', '--scope', $targetScope, 'view']);
if ($rulesResult['status'] !== 0) {
    approval_api_error(502, trim($rulesResult['error']) ?: trim($rulesResult['output']) ?: 'Unable to read approval rules.');
}
$scopeResult = approval_api_run(['approve', '--scope']);
if ($scopeResult['status'] !== 0) {
    approval_api_error(502, trim($scopeResult['error']) ?: trim($scopeResult['output']) ?: 'Unable to determine the approval scope.');
}
$rules = [];
foreach (preg_split('/\R/', $rulesResult['output']) as $line) {
    $line = rtrim($line, "\r");
    if ($line !== '') {
        $rules[] = $line;
    }
}
$scope = trim($scopeResult['output']) ?: 'default';
echo json_encode(['ok' => true, 'scope' => $scope, 'targetScope' => $targetScope, 'rules' => array_values(array_unique($rules))], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
