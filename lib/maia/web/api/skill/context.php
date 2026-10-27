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

function skill_context_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

function skill_context_run(array $arguments): array
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

$scope = (string) ($_GET['scope'] ?? 'session');
if (!in_array($scope, ['session', 'workspace', 'profile', 'home'], true)) {
    skill_context_error(400, 'Invalid skill scope.');
}

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
if ($method === 'GET') {
    $list = skill_context_run(['skill', '--scope', $scope, 'list', '--json']);
    if ($list['status'] !== 0) {
        skill_context_error(502, trim($list['error']) ?: 'Unable to list skills.');
    }

    $skills = [];
    foreach (preg_split('/\R/', trim($list['output'])) as $line) {
        if ($line === '') {
            continue;
        }
        try {
            $skill = json_decode($line, true, 512, JSON_THROW_ON_ERROR);
        } catch (JsonException) {
            skill_context_error(502, 'MAIA returned invalid skill data.');
        }
        if (!is_array($skill)) {
            continue;
        }
        $marker = (string) ($skill['marker'] ?? ' ');
        $skills[] = [
            'name' => (string) ($skill['name'] ?? ''),
            'description' => (string) ($skill['description'] ?? ''),
            'allowed' => $marker === '+' || $marker === '*',
            'memory' => $marker === '+' || $marker === 'E',
            'source' => (string) ($skill['source'] ?? ''),
        ];
    }

    $source = skill_context_run(['skill', '--scope']);
    if ($source['status'] !== 0) {
        skill_context_error(502, trim($source['error']) ?: 'Unable to resolve skill scope.');
    }
    $effectiveScope = trim($source['output']) ?: 'default';

    $patterns = skill_context_run(['skill', '--scope', $scope, '--type', 'allow', 'view']);
    if ($patterns['status'] !== 0) {
        skill_context_error(502, trim($patterns['error']) ?: 'Unable to read skill patterns.');
    }
    $patternLines = [];
    foreach (preg_split('/\R/', $patterns['output']) as $line) {
        $line = rtrim($line, "\r");
        if ($line !== '') {
            $patternLines[] = $line;
        }
    }

    echo json_encode([
        'ok' => true,
        'scope' => $effectiveScope,
        'requestedScope' => $scope,
        'patterns' => array_values(array_unique($patternLines)),
        'skills' => $skills,
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

if ($method !== 'POST') {
    header('Allow: GET, POST');
    skill_context_error(405, 'Method not allowed.');
}

$input = json_decode((string) (file_get_contents('php://input') ?: ''), true);
if (!is_array($input)) {
    skill_context_error(400, 'Invalid skill operation.');
}
$action = (string) ($input['action'] ?? '');

if ($action === 'refresh') {
    $refresh = skill_context_run(['skill', '--scope', $scope, 'refresh']);
    if ($refresh['status'] !== 0) {
        skill_context_error(502, trim($refresh['error']) ?: trim($refresh['output']) ?: 'Unable to refresh skills.');
    }
    echo json_encode(['ok' => true], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

if ($action === 'memory') {
    $name = trim((string) ($input['name'] ?? ''));
    $remember = (bool) ($input['remember'] ?? false);
    if ($name === '' || !preg_match('/^[A-Za-z0-9_.%+\-]+$/', $name)) {
        skill_context_error(400, 'Invalid skill name.');
    }
    $command = $remember ? 'append' : 'forget';
    $result = skill_context_run([
        'skill', '--scope', $scope, '--type', 'memory', $command, $name
    ]);
    if ($result['status'] !== 0) {
        skill_context_error(502, trim($result['error']) ?: trim($result['output']) ?: 'Unable to update skill memory.');
    }
    echo json_encode(['ok' => true, 'name' => $name, 'memory' => $remember], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

$pattern = trim((string) ($input['pattern'] ?? ''));
if ($action === 'append' || $action === 'disable') {
    if ($pattern === '' || str_contains($pattern, "\0") || str_contains($pattern, "\n") || str_contains($pattern, "\r")) {
        skill_context_error(400, 'A skill pattern is required.');
    }
    $command = $action === 'append' ? 'append' : 'disable';
    $result = skill_context_run(['skill', '--scope', $scope, '--type', 'allow', $command, $pattern]);
} elseif ($action === 'clear' || $action === 'delete') {
    $result = skill_context_run(['skill', '--scope', $scope, '--type', 'allow', $action]);
} else {
    skill_context_error(400, 'Unknown skill operation.');
}

if ($result['status'] !== 0) {
    skill_context_error(502, trim($result['error']) ?: trim($result['output']) ?: 'Unable to update skill definitions.');
}

echo json_encode(['ok' => true], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
