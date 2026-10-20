<?php

declare(strict_types=1);

require_once __DIR__ . '/../web.php';

header('Content-Type: application/json; charset=utf-8');

function session_settings_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode([
        'ok' => false,
        'error' => $message,
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

/** @return array{output: string, error: string, status: int} */
function session_settings_run(array $arguments, string $input = ''): array
{
    $process = proc_open(
        array_merge([maia_web_binary()], $arguments),
        [
            0 => ['pipe', 'r'],
            1 => ['pipe', 'w'],
            2 => ['pipe', 'w'],
        ],
        $pipes,
        null,
        maia_web_environment()
    );

    if (!is_resource($process)) {
        return ['output' => '', 'error' => 'Unable to start MAIA.', 'status' => 1];
    }

    if ($input !== '') {
        fwrite($pipes[0], $input);
    }
    fclose($pipes[0]);
    $output = (string) stream_get_contents($pipes[1]);
    fclose($pipes[1]);
    $error = (string) stream_get_contents($pipes[2]);
    fclose($pipes[2]);

    return [
        'output' => $output,
        'error' => $error,
        'status' => proc_close($process),
    ];
}

/** @return array<string, string> */
function session_settings_myl(string $text): array
{
    $values = [];
    foreach (preg_split('/\R/', $text) as $line) {
        if (preg_match('/^([^:[:space:]]+):[[:space:]]?(.*)$/', $line, $match)) {
            $values[$match[1]] = $match[2];
        }
    }
    return $values;
}

/** @return list<string> */
function session_settings_list(array $arguments): array
{
    $result = session_settings_run($arguments);
    if ($result['status'] !== 0) {
        return [];
    }

    $names = [];
    foreach (preg_split('/\R/', $result['output']) as $line) {
        if (preg_match('/^\s*[* ]\s+(\S+)/', $line, $match)) {
            $names[$match[1]] = true;
        } elseif (preg_match('/^\s*([A-Za-z0-9_.%+-]+)\s*$/', $line, $match)) {
            $names[$match[1]] = true;
        }
    }
    return array_keys($names);
}

function session_settings_values(): array
{
    // Profile and workspace pages use the reserved _EMPTY_ session context.
    // They still need the resource lists for the sidebar, but there is no
    // real session whose settings should be read.
    $profileContext = trim((string) ($_SERVER['HTTP_X_MAIA_PROFILE'] ?? $_SERVER['MAIA_URL_PROFILE'] ?? ''));
    $workspaceContext = trim((string) ($_SERVER['HTTP_X_MAIA_WORKSPACE'] ?? $_SERVER['MAIA_URL_WORKSPACE'] ?? ''));
    $homeContext = trim((string) ($_SERVER['HTTP_X_MAIA_HOME'] ?? $_SERVER['MAIA_URL_HOME'] ?? ''));
    $values = [];
    if ($profileContext === '' && $workspaceContext === '' && $homeContext === '') {
        $show = session_settings_run(['session', 'show', '--raw']);
        if ($show['status'] !== 0) {
            session_settings_error(502, trim($show['error']) ?: 'Unable to read session settings.');
        }
        $values = session_settings_myl($show['output']);
    }

    $decodeList = static function (?string $value): array {
        if ($value === null || trim($value) === '') {
            return [];
        }
        $decoded = json_decode($value, true);
        if (is_array($decoded)) {
            return array_values(array_map('strval', $decoded));
        }
        return array_values(array_filter(array_map('trim', explode(',', $value)), static fn ($v) => $v !== ''));
    };

    $workspaces = [];
    foreach (session_settings_list(['workspace', 'list', '--raw']) as $workspaceName) {
        $workspace = session_settings_run(['workspace', 'show', '--raw', $workspaceName]);
        if ($workspace['status'] !== 0) {
            continue;
        }
        $workspacePath = '';
        foreach (preg_split('/\R/', $workspace['output']) as $line) {
            if (preg_match('/^path:\s*(.*)$/', $line, $match)) {
                $workspacePath = trim($match[1]);
                break;
            }
        }
        if ($workspacePath !== '' && maia_web_path_within_home($workspacePath)) {
            $workspaces[] = $workspaceName;
        }
    }

    return [
        'workspace' => $values['workspace'] ?? '',
        'profile' => $values['profile'] ?? '',
        'filesets' => $decodeList($values['filesets'] ?? null),
        'extraSendFilesets' => $decodeList($values['extra_send_filesets'] ?? null),
        'workspaces' => $workspaces,
        'profiles' => session_settings_list(['profile', 'list', '--raw']),
        'filesetOptions' => array_values(array_unique(array_merge(
            ['__SESSION_NAME__', '__SESSION_WORKSPACE__'],
            session_settings_list(['filesets', 'list', '--raw'])
        ))),
    ];
}

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
if ($method === 'GET') {
    echo json_encode(['ok' => true] + session_settings_values(), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

if ($method !== 'POST') {
    header('Allow: GET, POST');
    session_settings_error(405, 'Method not allowed.');
}

$input = json_decode((string) (file_get_contents('php://input') ?: ''), true);
if (!is_array($input)) {
    session_settings_error(400, 'Invalid settings data.');
}

$toList = static function ($value): string {
    if (!is_array($value)) {
        return '';
    }
    return implode(',', array_map('strval', $value));
};

$arguments = [
    'session', 'set',
    '--workspace', (string) ($input['workspace'] ?? ''),
    '--profile', (string) ($input['profile'] ?? ''),
    '--filesets', $toList($input['filesets'] ?? []),
    '--extra-send-filesets', $toList($input['extraSendFilesets'] ?? []),
];

$updated = session_settings_run($arguments);
if ($updated['status'] !== 0) {
    session_settings_error(502, trim($updated['error']) ?: 'Unable to update session settings.');
}

echo json_encode(['ok' => true] + session_settings_values(), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
