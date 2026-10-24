<?php

declare(strict_types=1);

require_once __DIR__ . '/../web.php';

header('Content-Type: application/json; charset=utf-8');

function tool_context_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$input = [];
if ($method === 'POST') {
    $input = json_decode((string) (file_get_contents('php://input') ?: ''), true);
    if (!is_array($input)) {
        tool_context_error(400, 'Invalid tool operation.');
    }
} elseif ($method !== 'GET') {
    header('Allow: GET, POST');
    tool_context_error(405, 'Method not allowed.');
}

function tool_context_run(array $arguments): array
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

$scope = (string) ($_GET['scope'] ?? ($input['scope'] ?? 'session'));
if (!in_array($scope, ['session', 'workspace', 'profile', 'home'], true)) {
    tool_context_error(400, 'Invalid tool scope.');
}

if ($method === 'POST') {
    if (($input['action'] ?? '') !== 'refresh') {
        tool_context_error(400, 'Unknown tool operation.');
    }
    $refresh = tool_context_run(['tool', '--scope', $scope, 'refresh']);
    if ($refresh['status'] !== 0) {
        tool_context_error(502, trim($refresh['error']) ?: trim($refresh['output']) ?: 'Unable to refresh tools.');
    }
    echo json_encode(['ok' => true], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}
$patternsResult = tool_context_run(['tool', '--scope', $scope, 'view']);
if ($patternsResult['status'] !== 0) {
    tool_context_error(502, trim($patternsResult['error']) ?: 'Unable to read tool patterns.');
}
$patterns = [];
foreach (preg_split('/\R/', $patternsResult['output']) as $line) {
    $line = rtrim($line, "\r");
    if ($line !== '') {
        $patterns[] = $line;
    }
}

$sourceResult = tool_context_run(['tool', '--scope']);
$sourceFile = trim($sourceResult['output']);
$sourceScope = $sourceFile === '' ? 'default' : $sourceFile;

$toolsResult = tool_context_run(['tool', '--scope', $scope, 'list', '--json']);
if ($toolsResult['status'] !== 0) {
    tool_context_error(502, trim($toolsResult['error']) ?: 'Unable to list tools.');
}
try {
    $tools = json_decode($toolsResult['output'], true, 512, JSON_THROW_ON_ERROR);
} catch (JsonException) {
    tool_context_error(502, 'MAIA returned invalid tool data.');
}
if (!is_array($tools)) {
    tool_context_error(502, 'MAIA returned an invalid tool list.');
}
$tools = array_map(static function (array $tool): array {
    return [
        'name' => (string) ($tool['name'] ?? ''),
        'description' => (string) ($tool['description'] ?? ''),
        'effects' => is_array($tool['effects'] ?? null) ? array_values($tool['effects']) : [],
        'allowed' => (bool) ($tool['allowed'] ?? false),
        'source' => (string) ($tool['source'] ?? ''),
    ];
}, $tools);

echo json_encode([
    'ok' => true,
    'patterns' => array_values(array_unique($patterns)),
    'scope' => $sourceScope,
    'scopeFile' => $sourceFile,
    'tools' => $tools,
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
