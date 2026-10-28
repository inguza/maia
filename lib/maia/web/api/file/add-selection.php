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

function file_selection_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? 'POST') !== 'POST') {
    header('Allow: POST');
    file_selection_error(405, 'Method not allowed.');
}
$session = trim((string) ($_SERVER['HTTP_X_MAIA_SESSION'] ?? ''));
$workspace = trim((string) ($_SERVER['HTTP_X_MAIA_WORKSPACE'] ?? $_SERVER['MAIA_URL_WORKSPACE'] ?? ''));
if (!preg_match('/^[A-Za-z0-9_.%+\-]+$/', $session) || $session === '_EMPTY_') file_selection_error(400, 'A target session is required.');
if ($workspace === '' || !preg_match('/^[A-Za-z0-9_.%+\-]+$/', $workspace)) file_selection_error(400, 'A workspace is required.');
$input = json_decode((string) file_get_contents('php://input'), true);
$content = is_array($input) ? (string) ($input['content'] ?? '') : '';
$label = is_array($input) ? trim((string) ($input['label'] ?? 'selection')) : 'selection';
if ($content === '') file_selection_error(400, 'The selection is empty.');
if (strlen($content) > 2 * 1024 * 1024) file_selection_error(413, 'The selection is too large.');
$home = maia_web_home_dir();
$meta = $home . DIRECTORY_SEPARATOR . 'workspaces' . DIRECTORY_SEPARATOR . $workspace . DIRECTORY_SEPARATOR . 'workspace.myl';
$root = '';
foreach (is_file($meta) ? (file($meta, FILE_IGNORE_NEW_LINES) ?: []) : [] as $line) {
    if (preg_match('/^path:\s*(.*)$/', $line, $m)) { $root = trim($m[1]); break; }
}
$root = realpath($root);
if ($root === false || !is_dir($root)) file_selection_error(403, 'The workspace root is unavailable.');
$dir = $root . DIRECTORY_SEPARATOR . '.maia-context';
if (!is_dir($dir) && !mkdir($dir, 0775, true)) file_selection_error(500, 'Unable to create the selection directory.');
$safeLabel = preg_replace('/[^A-Za-z0-9_.-]+/', '_', basename($label)) ?: 'selection';
$fileName = $safeLabel . '-' . substr(hash('sha256', $session . microtime(true) . $content), 0, 12) . '.txt';
$relative = '.maia-context/' . $fileName;
if (file_put_contents($dir . DIRECTORY_SEPARATOR . $fileName, $content) === false) file_selection_error(500, 'Unable to save the selection.');
$process = proc_open(
    [maia_web_binary(), 'file', 'add', $relative],
    [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
    $pipes, $root, maia_web_environment()
);
if (!is_resource($process)) file_selection_error(500, 'Unable to add the selection to the session.');
fclose($pipes[0]);
$output = (string) stream_get_contents($pipes[1]); fclose($pipes[1]);
$error = (string) stream_get_contents($pipes[2]); fclose($pipes[2]);
$status = proc_close($process);
if ($status !== 0) file_selection_error(502, trim($error) ?: trim($output) ?: 'Unable to add the selection to the session.');
echo json_encode(['ok' => true, 'path' => $relative], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
