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

if (($_SERVER['REQUEST_METHOD'] ?? 'POST') !== 'POST') {
    header('Allow: POST');
    http_response_code(405);
    echo json_encode(['ok' => false, 'error' => 'Method not allowed.']) . "\n";
    exit;
}

$process = proc_open(
    [maia_binary(), 'tool', '--scope', (string) ($_GET['scope'] ?? 'session'), 'clear'],
    [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
    $pipes,
    null,
    maia_environment()
);
if (!is_resource($process)) {
    http_response_code(500);
    echo json_encode(['ok' => false, 'error' => 'Unable to start MAIA.']) . "\n";
    exit;
}
fclose($pipes[0]);
$output = (string) stream_get_contents($pipes[1]); fclose($pipes[1]);
$error = (string) stream_get_contents($pipes[2]); fclose($pipes[2]);
$status = proc_close($process);
if ($status !== 0) {
    http_response_code(502);
    echo json_encode(['ok' => false, 'error' => trim($error) ?: trim($output) ?: 'Unable to clear tool definitions.']) . "\n";
    exit;
}
echo json_encode(['ok' => true], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
