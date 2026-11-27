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

function history_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode([
        'ok' => false,
        'error' => $message,
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

/** @return array{status: int, output: string, error: string} */
function history_run_cli(array $arguments): array
{
    $process = proc_open(
        array_merge([getenv('MAIA_BIN') ?: 'maia'], $arguments),
        [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
        $pipes,
        null,
        maia_environment()
    );
    if (!is_resource($process)) {
        return ['status' => 500, 'output' => '', 'error' => 'Unable to start MAIA.'];
    }
    fclose($pipes[0]);
    $output = (string) stream_get_contents($pipes[1]);
    fclose($pipes[1]);
    $error = (string) stream_get_contents($pipes[2]);
    fclose($pipes[2]);
    return ['status' => proc_close($process), 'output' => $output, 'error' => $error];
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: POST');
    history_error(405, 'Method not allowed.');
}

$stickyOnly = (string) ($_GET['stickyOnly'] ?? '') === '1';
$includeSticky = !$stickyOnly && (string) ($_GET['includeSticky'] ?? '1') !== '0';
$range = trim((string) (file_get_contents('php://input') ?: ''));
if (!$stickyOnly && $range === '') {
    history_error(400, 'History range cannot be empty.');
}

$history = [];
$rangeItemCount = 0;
$rangeFirstIndex = null;
$rangeLastIndex = null;
$rangeFirstId = null;
$rangeLastId = null;
if (!$stickyOnly) {
    $rangeResult = history_run_cli(['history', '--raw', $range]);
    if ($rangeResult['status'] !== 0) {
        history_error($rangeResult['status'] === 500 ? 500 : 502,
            trim($rangeResult['error']) ?: 'MAIA returned an error.');
    }
    try {
        $history = json_decode($rangeResult['output'], true, 512, JSON_THROW_ON_ERROR);
    } catch (JsonException $exception) {
        history_error(502, 'MAIA returned invalid history data.');
    }
    if (!is_array($history)) {
        history_error(502, 'MAIA returned an invalid history list.');
    }
    $rangeItemCount = count($history);
    $rangeFirstIndex = $history[0]['index'] ?? null;
    $rangeLastIndex = $history === [] ? null : $history[array_key_last($history)]['index'] ?? null;
    $rangeFirstId = $history[0]['id'] ?? null;
    $rangeLastId = $history === [] ? null : $history[array_key_last($history)]['id'] ?? null;
}

$stickyItems = [];
if ($includeSticky || $stickyOnly) {
    // Sticky entries can be fetched separately so the first requested history
    // range is displayed without waiting for this additional CLI lookup.
    $stickyResult = history_run_cli(['history', '--raw', '--sticky']);
    if ($stickyResult['status'] !== 0) {
        history_error($stickyResult['status'] === 500 ? 500 : 502,
            trim($stickyResult['error']) ?: 'Unable to load sticky history entries.');
    }
    try {
        $stickyItems = json_decode($stickyResult['output'], true, 512, JSON_THROW_ON_ERROR);
    } catch (JsonException $exception) {
        history_error(502, 'MAIA returned invalid sticky history data.');
    }
    if (!is_array($stickyItems)) {
        history_error(502, 'MAIA returned an invalid sticky history list.');
    }
}
$itemsByIndex = [];
foreach (array_merge($history, $stickyItems) as $item) {
    if (!is_array($item)) continue;
    $key = isset($item['index']) ? (string) $item['index'] : 'item:' . count($itemsByIndex);
    $itemsByIndex[$key] = $item;
}
$history = array_values($itemsByIndex);
usort($history, static fn (array $a, array $b): int => (int) ($a['index'] ?? 0) <=> (int) ($b['index'] ?? 0));

echo json_encode([
    'ok' => true,
    'range' => $range,
    'firstIndex' => $rangeFirstIndex,
    'lastIndex' => $rangeLastIndex,
    'firstId' => $rangeFirstId,
    'lastId' => $rangeLastId,
    'rangeItemCount' => $rangeItemCount,
    'items' => $history,
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
