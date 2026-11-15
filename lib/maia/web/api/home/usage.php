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
header('Cache-Control: no-store');

function home_usage_api_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
    header('Allow: GET');
    home_usage_api_error(405, 'Method not allowed.');
}

/** @return array{output: string, error: string, status: int} */
function home_usage_api_run(array $arguments): array
{
    $process = proc_open(
        array_merge([maia_binary()], $arguments),
        [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
        $pipes,
        null,
        maia_environment()
    );
    if (!is_resource($process)) {
        return ['output' => '', 'error' => 'Unable to start MAIA.', 'status' => 1];
    }

    fclose($pipes[0]);
    $output = (string) stream_get_contents($pipes[1]);
    fclose($pipes[1]);
    $error = trim((string) stream_get_contents($pipes[2]));
    fclose($pipes[2]);
    return ['output' => $output, 'error' => $error, 'status' => proc_close($process)];
}

$result = home_usage_api_run(['home', 'usage', '--json']);
if ($result['status'] !== 0) {
    home_usage_api_error(502, $result['error'] !== '' ? $result['error'] : 'Unable to read home usage.');
}

try {
    $summary = json_decode($result['output'], true, 512, JSON_THROW_ON_ERROR);
} catch (JsonException $exception) {
    home_usage_api_error(502, 'MAIA returned invalid home usage.');
}
if (!is_array($summary) || !is_array($summary['home'] ?? null) || !is_array($summary['today'] ?? null)) {
    home_usage_api_error(502, 'MAIA returned an invalid home usage summary.');
}

foreach (['home', 'today'] as $period) {
    foreach (['input', 'cached', 'output', 'reasoning'] as $category) {
        if (!is_int($summary[$period][$category] ?? null)) {
            home_usage_api_error(502, 'MAIA returned an invalid home usage summary.');
        }
    }
}

echo json_encode([
    'ok' => true,
    'home' => $summary['home'],
    'today' => $summary['today'],
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
