<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */

declare(strict_types=1);

require_once __DIR__ . '/../web.php';

header('Content-Type: application/json; charset=utf-8');

function auth_context_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

function auth_context_run(array $arguments): array
{
    $process = proc_open(
        array_merge([maia_web_binary()], $arguments),
        [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
        $pipes,
        null,
        maia_web_environment()
    );
    if (!is_resource($process)) {
        return ['output' => '', 'error' => 'Unable to start MAIA.', 'status' => 1];
    }
    fclose($pipes[0]);
    $output = (string) stream_get_contents($pipes[1]);
    fclose($pipes[1]);
    $error = (string) stream_get_contents($pipes[2]);
    fclose($pipes[2]);
    return ['output' => $output, 'error' => $error, 'status' => proc_close($process)];
}

function auth_context_list(): array
{
    $result = auth_context_run(['gui', 'list']);
    if ($result['status'] !== 0) {
        auth_context_error(502, trim($result['error']) ?: 'Unable to list credentials.');
    }

    $credentials = [];
    foreach (preg_split('/\R/', $result['output']) as $line) {
        if (preg_match('/^([A-Za-z0-9_-]+):([0-9a-f]+)$/', trim($line), $match)) {
            $credentials[] = [
                'name' => $match[1],
                'salt' => $match[2],
                'identifier' => $match[0],
            ];
        }
    }
    return $credentials;
}

function auth_context_public_url(): string
{
    $scheme = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
    $host = trim((string) ($_SERVER['HTTP_HOST'] ?? ''));
    if ($host === '' || !preg_match('/^[A-Za-z0-9.:[\]-]+(?::[0-9]+)?$/', $host)) {
        auth_context_error(400, 'Unable to determine the public MAIA host.');
    }
    return $scheme . '://' . $host . maia_web_base_path();
}

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
if ($method === 'GET') {
    echo json_encode(['ok' => true, 'credentials' => auth_context_list()], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}
if ($method !== 'POST') {
    header('Allow: GET, POST');
    auth_context_error(405, 'Method not allowed.');
}

$input = json_decode((string) (file_get_contents('php://input') ?: ''), true);
if (!is_array($input)) {
    auth_context_error(400, 'Invalid credential operation.');
}
$action = (string) ($input['action'] ?? '');

if ($action === 'create') {
    $name = trim((string) ($input['name'] ?? ''));
    if ($name !== '' && !preg_match('/^[A-Za-z0-9_-]+$/', $name)) {
        auth_context_error(400, 'Invalid credential name. Use only letters, digits, underscore and hyphen.');
    }
    $arguments = ['gui', 'create'];
    if ($name !== '') {
        $arguments[] = $name;
    }
    $arguments[] = '--url';
    $arguments[] = auth_context_public_url();
    $result = auth_context_run($arguments);
    if ($result['status'] !== 0) {
        auth_context_error(502, trim($result['error']) ?: trim($result['output']) ?: 'Unable to create the credential.');
    }
    $guiUrl = '';
    $qrUrl = '';
    foreach (preg_split('/\R/', $result['output']) as $line) {
        if (preg_match('/^MAIA GUI:\s*(\S+)$/', trim($line), $match)) {
            $guiUrl = $match[1];
        } elseif (preg_match('/^MAIA QR:\s*(\S+)$/', trim($line), $match)) {
            $qrUrl = $match[1];
        }
    }
    $credentials = auth_context_list();
    $created = null;
    $createdName = $name !== '' ? $name : 'auto';
    $createdSalt = '';
    if (preg_match('/#auth=([0-9a-f]+):[0-9a-f]+$/', $guiUrl, $match)) {
        $createdSalt = $match[1];
    }
    foreach ($credentials as $credential) {
        if ($credential['name'] === $createdName &&
            ($createdSalt === '' || $credential['salt'] === $createdSalt)) {
            $created = $credential;
            break;
        }
    }
    echo json_encode([
        'ok' => true,
        'credential' => $created,
        'url' => $guiUrl,
        'qrUrl' => $qrUrl,
        'credentials' => $credentials,
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

if ($action === 'delete') {
    $identifier = trim((string) ($input['identifier'] ?? ''));
    if (!preg_match('/^[A-Za-z0-9_-]+:[0-9a-f]+$/', $identifier)) {
        auth_context_error(400, 'Invalid credential identifier.');
    }
    $result = auth_context_run(['gui', 'delete', $identifier]);
    if ($result['status'] !== 0) {
        auth_context_error(502, trim($result['error']) ?: trim($result['output']) ?: 'Unable to delete the credential.');
    }
    echo json_encode(['ok' => true, 'credentials' => auth_context_list()], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

auth_context_error(400, 'Unknown credential operation.');
