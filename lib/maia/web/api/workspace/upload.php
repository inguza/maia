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

function workspace_upload_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? 'POST') !== 'POST') {
    header('Allow: POST');
    workspace_upload_error(405, 'Method not allowed.');
}
$name = trim((string) ($_SERVER['HTTP_X_MAIA_WORKSPACE'] ?? $_SERVER['MAIA_URL_WORKSPACE'] ?? ''));
if ($name === '' || !preg_match('/^[A-Za-z0-9_.%+\-]+$/', $name)) workspace_upload_error(400, 'A workspace is required.');
$root = maia_workspace_root_path($name);
if ($root === null || !maia_workspace_is_usable($name)) workspace_upload_error(404, 'Workspace is not available to the web interface.');
$relative = str_replace('\\', '/', trim((string) ($_POST['path'] ?? ''), " /\\"));
if ($relative !== '' && preg_match('/(^|\/)(\.\.?)(\/|$)/', $relative)) workspace_upload_error(400, 'Invalid upload directory.');
$directory = $relative === '' ? $root : realpath($root . DIRECTORY_SEPARATOR . str_replace('/', DIRECTORY_SEPARATOR, $relative));
$prefix = rtrim($root, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR;
if ($directory === false || !is_dir($directory) || ($directory !== $root && !str_starts_with($directory, $prefix))) workspace_upload_error(403, 'Upload directory is outside the workspace.');
if (!isset($_FILES['file']) || !is_array($_FILES['file']) || ($_FILES['file']['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) workspace_upload_error(400, 'No upload was received.');
$filename = basename((string) $_FILES['file']['name']);
if ($filename === '' || $filename === '.' || $filename === '..' || str_contains($filename, '/') || str_contains($filename, '\\')) workspace_upload_error(400, 'Invalid file name.');
$target = $directory . DIRECTORY_SEPARATOR . $filename;
if (file_exists($target)) workspace_upload_error(409, 'A file with that name already exists.');
if (!move_uploaded_file((string) $_FILES['file']['tmp_name'], $target)) workspace_upload_error(500, 'Unable to store uploaded file.');
echo json_encode(['ok' => true, 'path' => ($relative === '' ? '' : $relative . '/') . $filename], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
