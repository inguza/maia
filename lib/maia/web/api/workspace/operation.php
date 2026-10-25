<?php

declare(strict_types=1);

require_once __DIR__ . '/../web.php';
header('Content-Type: application/json; charset=utf-8');

function workspace_operation_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

/** @return array{kind: string, mime: string} */
function workspace_operation_file_type(string $file): array
{
    $sample = @file_get_contents($file, false, null, 0, 65536);
    if ($sample !== false) {
        $binary = str_contains($sample, "\0") || preg_match('//u', $sample) !== 1;
        if (!$binary && preg_match_all('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/', $sample, $matches) > max(1, (int) (strlen($sample) / 100))) {
            $binary = true;
        }
        if (!$binary) {
            return ['kind' => 'text', 'mime' => 'text/plain'];
        }
    }

    $mime = '';
    $process = proc_open(
        ['file', '--brief', '--mime-type', '--', $file],
        [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
        $pipes
    );
    if (is_resource($process)) {
        fclose($pipes[0]);
        $mime = trim((string) stream_get_contents($pipes[1]));
        fclose($pipes[1]);
        fclose($pipes[2]);
        proc_close($process);
    }

    if ($mime === '') {
        $header = @file_get_contents($file, false, null, 0, 16) ?: '';
        if (str_starts_with($header, "\x89PNG\r\n\x1a\n")) $mime = 'image/png';
        elseif (str_starts_with($header, "\xff\xd8\xff")) $mime = 'image/jpeg';
        elseif (str_starts_with($header, 'GIF87a') || str_starts_with($header, 'GIF89a')) $mime = 'image/gif';
        elseif (substr($header, 0, 4) === 'RIFF' && substr($header, 8, 4) === 'WEBP') $mime = 'image/webp';
        elseif (str_starts_with($header, '%PDF-')) $mime = 'application/pdf';
    }

    return ['kind' => 'binary', 'mime' => $mime !== '' ? $mime : 'application/octet-stream'];
}

function workspace_operation_inline_mime(string $mime): bool
{
    return str_starts_with($mime, 'image/') ||
        str_starts_with($mime, 'audio/') ||
        str_starts_with($mime, 'video/') ||
        $mime === 'application/pdf';
}

$workspaceName = trim((string) ($_SERVER['HTTP_X_MAIA_WORKSPACE'] ?? $_SERVER['MAIA_URL_WORKSPACE'] ?? $_GET['workspace'] ?? ''));
if ($workspaceName === '' || !preg_match('/^[A-Za-z0-9_.%+\-]+$/', $workspaceName)) {
    workspace_operation_error(400, 'A workspace is required.');
}
$home = maia_web_home_dir();
$meta = $home . DIRECTORY_SEPARATOR . 'workspaces' . DIRECTORY_SEPARATOR . $workspaceName . DIRECTORY_SEPARATOR . 'workspace.myl';
$root = '';
foreach (is_file($meta) ? (file($meta, FILE_IGNORE_NEW_LINES) ?: []) : [] as $line) {
    if (preg_match('/^path:\s*(.*)$/', $line, $match)) { $root = trim($match[1]); break; }
}
if ($root !== '' && $root[0] !== '/' && !preg_match('/^[A-Za-z]:[\\\/]/', $root)) {
    $root = $home . DIRECTORY_SEPARATOR . $root;
}
$root = realpath($root);
if ($root === false || !is_dir($root)) {
    workspace_operation_error(403, 'The workspace root is unavailable.');
}
$prefix = rtrim($root, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR;
$relative = static function ($value): string {
    $value = str_replace('\\', '/', trim((string) $value));
    if ($value === '' || $value === '.') return '';
    if ($value[0] === '/' || preg_match('/^[A-Za-z]:\//', $value)) workspace_operation_error(400, 'Paths must be relative.');
    $parts = [];
    foreach (explode('/', $value) as $part) {
        if ($part === '' || $part === '.') continue;
        if ($part === '..' || str_contains($part, "\0") || str_contains($part, "\n") || str_contains($part, "\r")) workspace_operation_error(400, 'Invalid workspace path.');
        $parts[] = $part;
    }
    return implode('/', $parts);
};
$existing = static function (string $path) use ($root, $prefix): string {
    $full = $path === '' ? $root : $root . DIRECTORY_SEPARATOR . str_replace('/', DIRECTORY_SEPARATOR, $path);
    $resolved = realpath($full);
    if ($resolved === false || ($resolved !== $root && !str_starts_with($resolved, $prefix))) workspace_operation_error(403, 'Path is outside the workspace.');
    return $resolved;
};
$parent = static function (string $path) use ($root, $prefix): string {
    $full = $root . DIRECTORY_SEPARATOR . str_replace('/', DIRECTORY_SEPARATOR, $path);
    $resolved = realpath(dirname($full));
    if ($resolved === false || ($resolved !== $root && !str_starts_with($resolved, $prefix))) workspace_operation_error(403, 'Destination is outside the workspace.');
    return $full;
};

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
if ($method === 'GET') {
    $path = $relative($_GET['path'] ?? '');
    $file = $existing($path);
    if (!is_file($file)) workspace_operation_error(400, 'Only files can be downloaded.');
    $fileType = workspace_operation_file_type($file);
    $kind = $fileType['kind'];
    $mime = $fileType['mime'];
    if (isset($_GET['raw'])) {
        header('X-Content-Type-Options: nosniff');
        header('Content-Type: ' . $mime);
        $inline = workspace_operation_inline_mime($mime);
        header('Content-Disposition: ' . ($inline ? 'inline' : 'attachment') . '; filename="' . addslashes(basename($file)) . '"');
        readfile($file);
        exit;
    }
    if (isset($_GET['view'])) {
        if ($kind !== 'text') {
            echo json_encode([
                'ok' => true,
                'path' => $path,
                'name' => basename($file),
                'kind' => 'binary',
                'mime' => $mime,
            ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
            exit;
        }
        if (filesize($file) > 2 * 1024 * 1024) workspace_operation_error(413, 'Files larger than 2 MB cannot be viewed.');
        $content = file_get_contents($file);
        if ($content === false) workspace_operation_error(415, 'This file cannot be viewed as text.');
        echo json_encode(['ok' => true, 'path' => $path, 'name' => basename($file), 'kind' => 'text', 'content' => $content], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
        exit;
    }
    header('X-Content-Type-Options: nosniff');
    header('Content-Type: ' . $mime);
    header('Content-Disposition: attachment; filename="' . addslashes(basename($file)) . '"');
    readfile($file);
    exit;
}
if ($method !== 'POST' && $method !== 'PUT' && $method !== 'DELETE') {
    header('Allow: GET, POST, PUT, DELETE');
    workspace_operation_error(405, 'Method not allowed.');
}
$input = json_decode((string) (file_get_contents('php://input') ?: ''), true);
if (!is_array($input)) $input = [];
$action = (string) ($input['action'] ?? ($method === 'DELETE' ? 'delete' : ''));
$path = $relative($input['path'] ?? '');
if ($action !== 'mkdir' && $path === '') workspace_operation_error(400, 'A path is required.');
$source = $path === '' ? $root : $existing($path);
$destinationPath = $relative($input['destination'] ?? '');
$name = trim((string) ($input['name'] ?? ''));
if ($action === 'mkdir') {
    if ($name !== '' && (str_contains($name, '/') || str_contains($name, '\\') || $name === '.' || $name === '..')) {
        workspace_operation_error(400, 'A valid directory name is required.');
    }
    $target = $parent($path);
    if ($name !== '') $target .= DIRECTORY_SEPARATOR . $name;
    elseif ($path !== '') $target = $root . DIRECTORY_SEPARATOR . str_replace('/', DIRECTORY_SEPARATOR, $path);
    if (file_exists($target)) workspace_operation_error(409, 'Destination already exists.');
    if (!mkdir($target, 0775, true)) workspace_operation_error(500, 'Unable to create directory.');
} elseif ($action === 'create') {
    $target = $parent($path);
    if (file_exists($target)) workspace_operation_error(409, 'File already exists.');
    if (file_put_contents($target, '') === false) workspace_operation_error(500, 'Unable to create file.');
} elseif ($action === 'rename') {
    if ($path === '' || $name === '' || str_contains($name, '/') || $name === '.' || $name === '..') workspace_operation_error(400, 'A valid new name is required.');
    $target = dirname($source) . DIRECTORY_SEPARATOR . $name;
    if (file_exists($target)) workspace_operation_error(409, 'Destination already exists.');
    if (!rename($source, $target)) workspace_operation_error(500, 'Unable to rename path.');
} elseif ($action === 'copy' || $action === 'move') {
    if ($destinationPath === '') workspace_operation_error(400, 'A destination is required.');
    $target = $root . DIRECTORY_SEPARATOR . str_replace('/', DIRECTORY_SEPARATOR, $destinationPath);
    $targetParent = realpath(dirname($target));
    if ($targetParent === false || ($targetParent !== $root && !str_starts_with($targetParent, $prefix))) workspace_operation_error(403, 'Destination is outside the workspace.');
    if (file_exists($target)) workspace_operation_error(409, 'Destination already exists.');
    if ($action === 'copy') {
        $ok = is_dir($source) ? mkdir($target, 0775, true) && (new RecursiveIteratorIterator(new RecursiveDirectoryIterator($source, FilesystemIterator::SKIP_DOTS), RecursiveIteratorIterator::SELF_FIRST)) !== null : copy($source, $target);
        if (is_dir($source)) { $it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($source, FilesystemIterator::SKIP_DOTS), RecursiveIteratorIterator::SELF_FIRST); foreach ($it as $item) { $dest = $target . DIRECTORY_SEPARATOR . $it->getSubPathName(); $item->isDir() ? mkdir($dest, 0775, true) : copy($item->getPathname(), $dest); } }
    } else $ok = rename($source, $target);
    if (!$ok) workspace_operation_error(500, "Unable to $action path.");
} elseif ($action === 'delete') {
    if ($path === '') workspace_operation_error(400, 'The workspace root cannot be deleted.');
    $ok = is_dir($source) ? (function () use ($source) { $it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($source, FilesystemIterator::SKIP_DOTS), RecursiveIteratorIterator::CHILD_FIRST); foreach ($it as $item) $item->isDir() ? rmdir($item->getPathname()) : unlink($item->getPathname()); return rmdir($source); })() : unlink($source);
    if (!$ok) workspace_operation_error(500, 'Unable to delete path.');
} elseif ($action === 'write') {
    if (!is_file($source) || strlen((string) ($input['content'] ?? '')) > 5 * 1024 * 1024) workspace_operation_error(400, 'Only text files up to 5 MB can be edited.');
    if (file_put_contents($source, (string) $input['content']) === false) workspace_operation_error(500, 'Unable to save file.');
} else workspace_operation_error(400, 'Unknown workspace file operation.');

echo json_encode(['ok' => true, 'path' => $path], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
