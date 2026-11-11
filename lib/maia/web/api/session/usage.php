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

function session_usage_api_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
    header('Allow: GET');
    session_usage_api_error(405, 'Method not allowed.');
}

$session = maia_selected_session();
if ($session === null || !preg_match('/^[A-Za-z0-9_.%+\\-]+$/', $session) || $session === '_EMPTY_') {
    session_usage_api_error(400, 'A valid session context is required.');
}

/** @return array{output: string, error: string, status: int} */
function session_usage_api_run(array $arguments): array
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

function session_usage_api_decode(array $result, string $description): array
{
    if ($result['status'] !== 0) {
        session_usage_api_error(502, $result['error'] !== '' ? $result['error'] : "Unable to read $description.");
    }
    try {
        $decoded = json_decode($result['output'], true, 512, JSON_THROW_ON_ERROR);
    } catch (JsonException $exception) {
        session_usage_api_error(502, "MAIA returned invalid $description.");
    }
    if (!is_array($decoded)) {
        session_usage_api_error(502, "MAIA returned invalid $description.");
    }
    return $decoded;
}

$summary = session_usage_api_decode(
    session_usage_api_run(['session', 'usage', '--json']),
    'usage summary'
);
if (!is_array($summary['session'] ?? null) || !is_array($summary['today'] ?? null) ||
    (!is_array($summary['last'] ?? null) && ($summary['last'] ?? null) !== null) ||
    (!is_int($summary['max_input_tokens'] ?? null) && ($summary['max_input_tokens'] ?? null) !== null)) {
    session_usage_api_error(502, 'MAIA returned an invalid usage summary.');
}

echo json_encode([
    'ok' => true,
    'session' => $summary['session'],
    'today' => $summary['today'],
    'last' => $summary['last'],
    'max_input_tokens' => $summary['max_input_tokens'], 
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
