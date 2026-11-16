<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 */

declare(strict_types=1);

require_once __DIR__ . '/common.php';
approval_api_require_post();
$input = json_decode((string) (file_get_contents('php://input') ?: ''), true);
if (!is_array($input)) {
    approval_api_error(400, 'Invalid approval change.');
}
$rule = approval_api_validate_rule(trim((string) ($input['rule'] ?? '')));
$replacement = approval_api_validate_rule(trim((string) ($input['replacement'] ?? '')));
$result = approval_api_run(['approve', '--scope', approval_api_scope(), 'change', $rule, $replacement]);
if ($result['status'] !== 0) {
    approval_api_error(502, trim($result['error']) ?: trim($result['output']) ?: 'Unable to change the approval rule.');
}
echo json_encode(['ok' => true], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
