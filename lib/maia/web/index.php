<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */

declare(strict_types=1);

require_once __DIR__ . '/api/web.php';

if (!maia_web_authenticate_page()) {
    exit;
}

function escape(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

$workspacePageName = trim((string) ($_SERVER['MAIA_URL_WORKSPACE'] ?? ''));
$workspacePagePath = trim(str_replace('\\', '/', (string) ($_SERVER['MAIA_URL_WORKSPACE_PATH'] ?? '')), '/');
$sessionWorkspacePage = (string) ($_SERVER['MAIA_URL_SESSION_WORKSPACE'] ?? '') === '1';
$workspacePageEdit = (string) ($_GET['edit'] ?? '') === '1';
$pureWorkspaceBrowserPage = $workspacePagePath !== '';
$profilePageName = trim((string) ($_SERVER['MAIA_URL_PROFILE'] ?? ''));
$homePage = trim((string) ($_SERVER['MAIA_URL_HOME'] ?? '')) !== '';
$webBasePath = maia_web_base_path();
$resourcePageName = $workspacePageName !== '' ? $workspacePageName : $profilePageName;
$isResourcePage = $resourcePageName !== '' || $homePage;
$initialSessionName = maia_web_initial_session() ?: 'No session selected';
$sessionWorkspaceName = (!$isResourcePage && $initialSessionName !== 'No session selected')
    ? (maia_web_session_workspace($initialSessionName) ?: '')
    : '';
$initialTitle = $sessionWorkspacePage
    ? 'session: ' . $initialSessionName . ' / workspace'
    : ($workspacePageName !== ''
        ? 'workspace: ' . $workspacePageName
        : ($profilePageName !== ''
        ? 'profile: ' . $profilePageName
            : ($homePage
                ? 'home'
                : 'session: ' . $initialSessionName)));

/** @return list<array{name: string, path: string, type: string, size: int|null, modified: int|null, empty: bool}> */
function maia_web_initial_workspace_entries(string $workspaceName, string $relativePath = ''): array
{
    $home = maia_web_home_dir();
    if ($home === null || $home === '') {
        return [];
    }

    // Workspace manifests are stored below MAIA home. Read the manifest
    // directly instead of starting the CLI for every workspace page load.
    $metadata = $home . DIRECTORY_SEPARATOR . 'workspaces' . DIRECTORY_SEPARATOR
        . $workspaceName . DIRECTORY_SEPARATOR . 'workspace.myl';
    if (!is_file($metadata)) {
        return [];
    }

    $workspaceRoot = '';
    foreach (file($metadata, FILE_IGNORE_NEW_LINES) ?: [] as $line) {
        if (preg_match('/^path:\\s*(.*)$/', $line, $match)) {
            $workspaceRoot = trim($match[1]);
            break;
        }
    }
    $workspaceRoot = realpath(maia_web_expand_home_path($workspaceRoot));
    if ($workspaceRoot === false || !is_dir($workspaceRoot)) {
        return [];
    }

    $rootPrefix = rtrim($workspaceRoot, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR;
    $relativeParts = [];
    foreach (explode('/', str_replace('\\', '/', $relativePath)) as $part) {
        if ($part === '' || $part === '.') {
            continue;
        }
        if ($part === '..') {
            return [];
        }
        $relativeParts[] = $part;
    }
    $relativePath = implode('/', $relativeParts);
    $directory = $relativePath === ''
        ? $workspaceRoot
        : realpath($workspaceRoot . DIRECTORY_SEPARATOR . str_replace('/', DIRECTORY_SEPARATOR, $relativePath));
    if ($directory === false || !is_dir($directory) ||
        ($directory !== $workspaceRoot && !str_starts_with($directory, $rootPrefix))) {
        return [];
    }
    $entries = [];
    foreach (scandir($directory) ?: [] as $name) {
        if ($name === '.' || $name === '..') {
            continue;
        }
        $fullPath = $directory . DIRECTORY_SEPARATOR . $name;
        $resolved = realpath($fullPath);
        if ($resolved === false || ($resolved !== $workspaceRoot && !str_starts_with($resolved, $rootPrefix))) {
            continue;
        }
        $isDirectory = is_dir($fullPath);
        $children = $isDirectory ? @scandir($fullPath) : false;
        $isEmptyDirectory = $isDirectory && $children !== false && count(array_diff($children, ['.', '..'])) === 0;
        $entries[] = [
            'name' => $name,
            'path' => ($relativePath === '' ? '' : $relativePath . '/') . $name,
            'type' => $isDirectory ? 'directory' : 'file',
            'size' => $isDirectory ? null : (is_file($fullPath) ? filesize($fullPath) : null),
            'modified' => @filemtime($fullPath) ?: null,
            'empty' => $isEmptyDirectory,
        ];
    }
    usort($entries, static function (array $a, array $b): int {
        return [$a['type'] !== 'directory', strtolower($a['name'])]
            <=> [$b['type'] !== 'directory', strtolower($b['name'])];
    });
    return $entries;
}

function maia_web_initial_workspace_file(string $workspaceName, string $relativePath): ?array
{
    if ($relativePath === '') {
        return null;
    }
    $home = maia_web_home_dir();
    if ($home === null || $home === '') {
        return null;
    }
    $metadata = $home . DIRECTORY_SEPARATOR . 'workspaces' . DIRECTORY_SEPARATOR
        . $workspaceName . DIRECTORY_SEPARATOR . 'workspace.myl';
    if (!is_file($metadata)) {
        return null;
    }
    $workspaceRoot = '';
    foreach (file($metadata, FILE_IGNORE_NEW_LINES) ?: [] as $line) {
        if (preg_match('/^path:\s*(.*)$/', $line, $match)) {
            $workspaceRoot = trim($match[1]);
            break;
        }
    }
    if ($workspaceRoot !== '' && $workspaceRoot[0] !== '/' &&
        !preg_match('/^[A-Za-z]:[\\\\\\\/]/', $workspaceRoot)) {
        $workspaceRoot = maia_web_expand_home_path($workspaceRoot);
    }
    $workspaceRoot = realpath($workspaceRoot);
    if ($workspaceRoot === false || !is_dir($workspaceRoot)) {
        return null;
    }
    $parts = [];
    foreach (explode('/', str_replace('\\\\', '/', $relativePath)) as $part) {
        if ($part === '' || $part === '.') {
            continue;
        }
        if ($part === '..') {
            return null;
        }
        $parts[] = $part;
    }
    $relative = implode('/', $parts);
    $file = realpath($workspaceRoot . DIRECTORY_SEPARATOR . str_replace('/', DIRECTORY_SEPARATOR, $relative));
    $prefix = rtrim($workspaceRoot, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR;
    if ($file === false || !is_file($file) ||
        ($file !== $workspaceRoot && !str_starts_with($file, $prefix)) ||
        filesize($file) > 2 * 1024 * 1024) {
        return null;
    }
    $content = file_get_contents($file);
    if ($content === false || strpos($content, "\0") !== false) {
        return null;
    }
    return [
        'path' => $relative,
        'name' => basename($file),
        'content' => $content,
    ];
}

function maia_web_initial_workspace_path_type(string $workspaceName, string $relativePath): string
{
    if ($relativePath === '') {
        return 'root';
    }
    $home = maia_web_home_dir();
    if ($home === null || $home === '') {
        return 'missing';
    }
    $metadata = $home . DIRECTORY_SEPARATOR . 'workspaces' . DIRECTORY_SEPARATOR
        . $workspaceName . DIRECTORY_SEPARATOR . 'workspace.myl';
    if (!is_file($metadata)) {
        return 'missing';
    }
    $workspaceRoot = '';
    foreach (file($metadata, FILE_IGNORE_NEW_LINES) ?: [] as $line) {
        if (preg_match('/^path:\s*(.*)$/', $line, $match)) {
            $workspaceRoot = trim($match[1]);
            break;
        }
    }
    if ($workspaceRoot !== '' && $workspaceRoot[0] !== '/' &&
        !preg_match('/^[A-Za-z]:[\\\\\\\/]/', $workspaceRoot)) {
        $workspaceRoot = maia_web_expand_home_path($workspaceRoot);
    }
    $workspaceRoot = realpath($workspaceRoot);
    if ($workspaceRoot === false || !is_dir($workspaceRoot)) {
        return 'missing';
    }
    $parts = [];
    foreach (explode('/', str_replace('\\\\', '/', $relativePath)) as $part) {
        if ($part === '' || $part === '.') {
            continue;
        }
        if ($part === '..') {
            return 'missing';
        }
        $parts[] = $part;
    }
    $target = realpath($workspaceRoot . DIRECTORY_SEPARATOR . str_replace('/', DIRECTORY_SEPARATOR, implode('/', $parts)));
    $prefix = rtrim($workspaceRoot, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR;
    if ($target === false || ($target !== $workspaceRoot && !str_starts_with($target, $prefix))) {
        return 'missing';
    }
    return is_dir($target) ? 'directory' : (is_file($target) ? 'file' : 'missing');
}

$initialWorkspaceName = $workspacePageName !== '' ? $workspacePageName : $sessionWorkspaceName;
$initialWorkspaceEntries = $initialWorkspaceName === ''
    ? []
    : maia_web_initial_workspace_entries($initialWorkspaceName, $workspacePagePath);
$initialWorkspaceFile = $initialWorkspaceName === ''
    ? null
    : maia_web_initial_workspace_file($initialWorkspaceName, $workspacePagePath);
$initialWorkspacePathType = $initialWorkspaceName === ''
    ? 'missing'
    : maia_web_initial_workspace_path_type($initialWorkspaceName, $workspacePagePath);
if (session_status() === PHP_SESSION_ACTIVE) {
    session_write_close();
}

?>
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>MAIA - <?= escape($initialTitle) ?></title>
    <style>
        :root {
            color-scheme: light dark;
            font-family: system-ui, sans-serif;
        }

        body {
            margin: 0;
            padding: 1rem 1rem 1rem 4rem;
        }

        body::before {
            background: Canvas;
            border-right: 1px solid #d1d5db;
            bottom: 0;
            content: '';
            left: 0;
            position: fixed;
            top: 0;
            width: 3rem;
            z-index: 25;
        }

        .topbar > #sidebar-toggle {
            left: 0.55rem;
            margin: 0;
            position: fixed;
            top: 1rem;
            z-index: 31;
        }

        body.sidebar-open::before,
        body.sidebar-open .topbar > #sidebar-toggle {
            display: none;
        }

        body.sidebar-open .sidebar {
            left: 0;
        }

        body.sidebar-open .sidebar-backdrop {
            left: 0;
        }

        .app {
            margin: 0;
            max-width: none;
            width: 100%;
        }

        .sidebar-rail {
            align-items: flex-start;
            background: Canvas;
            border-right: 1px solid #d1d5db;
            bottom: 0;
            display: flex;
            justify-content: center;
            left: 0;
            padding-top: 1rem;
            position: fixed;
            top: 0;
            width: 3rem;
            z-index: 30;
        }

        .sidebar-rail .sidebar-toggle {
            margin: 0;
        }

        .topbar {
            align-items: center;
            display: flex;
            gap: 0.75rem;
            margin-bottom: 1rem;
        }

        .topbar h1 {
            font-size: 1.5rem;
            margin: 0;
        }

        .topbar .session-title-rename {
            margin: 0;
            padding: 0.25rem 0.45rem;
        }

        .session-workspace-session-link,
        .session-workspace-session-link:visited {
            color: inherit;
            text-decoration: none;
        }

        .session-workspace-session-link:hover,
        .session-workspace-session-link:focus {
            color: #000000;
            text-decoration: underline;
        }

        .sidebar-toggle,
        .sidebar-close {
            border: 0;
            cursor: pointer;
            margin: 0;
            padding: 0.35rem 0.6rem;
        }

        .sidebar-toggle {
            font-size: 1.25rem;
        }

        .sidebar {
            background: Canvas;
            border-right: 1px solid #d1d5db;
            bottom: 0;
            box-shadow: 0 0 1rem rgb(0 0 0 / 20%);
            left: 3rem;
            overflow-y: auto;
            padding: 1rem;
            position: fixed;
            top: 0;
            transform: translateX(-105%);
            transition: transform 0.2s ease;
            width: min(18rem, 80vw);
            z-index: 20;
        }

        .sidebar.open {
            transform: translateX(0);
        }

        .sidebar-header {
            align-items: center;
            display: flex;
            justify-content: space-between;
            margin-bottom: 1.5rem;
        }

        .sidebar-header h2 {
            font-size: 1.2rem;
            margin: 0;
        }

        .sidebar-section {
            margin-bottom: 1.5rem;
        }

        .sidebar-section h3 {
            font-size: 0.85rem;
            margin: 0 0 0.5rem;
            text-transform: uppercase;
        }

        .visually-hidden {
            clip: rect(0 0 0 0);
            clip-path: inset(50%);
            height: 1px;
            overflow: hidden;
            position: absolute;
            white-space: nowrap;
            width: 1px;
        }

        .session-search,
        .resource-search {
            display: flex;
            gap: 0.35rem;
            margin-bottom: 0.5rem;
        }

        .session-search input,
        .resource-search input {
            box-sizing: border-box;
            min-width: 0;
            padding: 0.4rem 0.5rem;
            width: 100%;
        }

        .session-search button,
        .resource-search button {
            margin: 0;
            padding: 0.35rem 0.65rem;
        }

        .sidebar-placeholder {
            color: #6b7280;
            font-size: 0.9rem;
            margin: 0;
        }

        .session-loading {
            align-items: center;
            color: #6b7280;
            display: flex;
            font-size: 0.85rem;
            gap: 0.5rem;
            margin: 0.5rem 0 0;
        }

        .session-loading[hidden] {
            display: none;
        }

        .spinner {
            animation: spin 0.8s linear infinite;
            border: 2px solid #d1d5db;
            border-radius: 50%;
            border-top-color: #4b5563;
            display: inline-block;
            height: 0.8rem;
            width: 0.8rem;
        }

        @keyframes spin {
            to { transform: rotate(360deg); }
        }

        .sidebar-list {
            list-style: none;
            margin: 0;
            max-height: min(16vh, 8rem);
            overflow-y: auto;
            overscroll-behavior: contain;
            padding: 0;
        }

        .sidebar-list button,
        .sidebar-list a.sidebar-resource-name {
            background: transparent;
            border: 0;
            border-radius: 0.35rem;
            cursor: pointer;
            display: block;
            margin: 0;
            padding: 0.4rem 0.5rem;
            text-align: left;
            width: 100%;
        }

        .sidebar-list a.sidebar-resource-name {
            color: inherit;
            text-decoration: none;
        }

        .session-item {
            align-items: center;
            display: flex;
            gap: 0.25rem;
        }

        .session-item.session-drop-target {
            outline: 2px dashed #2563eb;
            outline-offset: 2px;
        }

        .session-item > .sidebar-resource-name:first-child,
        .sidebar-list li > a.sidebar-resource-name {
            flex: 1;
            min-width: 0;
            width: auto;
        }

        .session-delete {
            color: #6b7280;
            flex: 0 0 auto;
            font-size: 0.85rem;
            padding: 0.25rem 0.45rem !important;
            width: auto !important;
        }

        .session-delete:hover {
            background: #fee2e2 !important;
            color: #991b1b;
        }

        .session-rename,
        .session-copy {
            color: #6b7280;
            flex: 0 0 auto;
            font-size: 0.95rem;
            padding: 0.25rem 0.45rem !important;
            width: auto !important;
        }

        .session-rename:hover,
        .session-copy:hover {
            background: #e5e7eb !important;
            color: #111827;
        }

        .session-item-actions {
            flex: 0 0 auto;
            position: relative;
        }

        .session-item-actions-toggle {
            color: #6b7280;
            margin: 0;
            padding: 0.25rem 0.45rem !important;
            width: auto !important;
        }

        .session-item-actions-menu {
            background: Canvas;
            border: 1px solid #9ca3af;
            border-radius: 0.35rem;
            box-shadow: 0 0.35rem 0.8rem rgb(0 0 0 / 20%);
            display: flex;
            flex-direction: column;
            min-width: 10rem;
            padding: 0.25rem;
            position: absolute;
            right: 0;
            top: calc(100% + 0.2rem);
            z-index: 15;
        }

        .session-item-actions-menu-floating,
        .session-more-tools-floating {
            box-sizing: border-box;
            max-width: calc(100vw - 1rem);
            max-height: calc(100vh - 1rem);
            overflow-x: hidden;
            overflow-y: auto;
            overscroll-behavior: contain;
            position: fixed !important;
            right: auto !important;
            bottom: auto !important;
            scrollbar-width: none;
            z-index: 1000 !important;
        }

        .session-item-actions-menu-floating::-webkit-scrollbar,
        .session-more-tools-floating::-webkit-scrollbar {
            display: none;
            width: 0;
        }

        .session-more-tools-floating {
            background: Canvas;
            border: 1px solid #9ca3af;
            border-radius: 0.35rem;
            box-shadow: 0 0.35rem 0.8rem rgb(0 0 0 / 20%);
            display: flex;
            flex-direction: column;
            min-width: 12rem;
            padding: 0.25rem;
        }

        .session-more-tools-floating button {
            align-items: center;
            background: transparent;
            border: 0;
            box-sizing: border-box;
            color: CanvasText;
            display: flex;
            justify-content: flex-start;
            margin: 0;
            min-width: 0;
            padding: 0.45rem 0.6rem;
            text-align: left;
            white-space: nowrap;
            width: 100%;
        }

        .session-more-tools-floating button:hover {
            background: #e5e7eb;
        }

        .session-item-actions-menu[hidden] {
            display: none;
        }

        .session-item-actions-menu button {
            align-items: center;
            background: transparent;
            border: 0;
            color: CanvasText;
            display: flex;
            gap: 0.55rem;
            margin: 0;
            padding: 0.4rem 0.55rem !important;
            text-align: left;
            width: 100% !important;
        }

        .session-item-actions-menu button:hover {
            background: #e5e7eb !important;
            color: #111827;
        }

        .session-delete-dialog {
            border: 1px solid #d1d5db;
            border-radius: 0.6rem;
            color: CanvasText;
            max-width: min(28rem, calc(100vw - 2rem));
            padding: 1.25rem;
        }

        .session-delete-dialog::backdrop {
            background: rgb(0 0 0 / 45%);
        }

        .session-delete-dialog h2 {
            font-size: 1.1rem;
            margin: 0 0 0.75rem;
        }

        .session-delete-dialog p {
            margin: 0;
            overflow-wrap: anywhere;
        }

        .session-delete-actions {
            display: flex;
            gap: 0.5rem;
            justify-content: flex-end;
            margin-top: 1.25rem;
        }

        .session-delete-actions button {
            margin: 0;
        }

        .session-delete-actions .danger {
            background: #b91c1c;
            color: #ffffff;
        }

        .resource-create-dialog {
            border: 1px solid #d1d5db;
            border-radius: 0.6rem;
            color: CanvasText;
            max-width: min(30rem, calc(100vw - 2rem));
            padding: 1.25rem;
        }

        .resource-create-dialog::backdrop {
            background: rgb(0 0 0 / 45%);
        }

        .resource-create-dialog h2 {
            font-size: 1.1rem;
            margin: 0 0 1rem;
        }

        .resource-create-dialog label {
            display: flex;
            flex-direction: column;
            gap: 0.25rem;
            margin-top: 0.75rem;
        }

        .completion-field {
            position: relative;
        }

        .resource-create-dialog label[hidden] {
            display: none;
        }

        .resource-settings-dialog {
            border: 1px solid #d1d5db;
            border-radius: 0.6rem;
            color: CanvasText;
            max-width: min(34rem, calc(100vw - 2rem));
            padding: 1.25rem;
        }

        .resource-settings-dialog::backdrop {
            background: rgb(0 0 0 / 45%);
        }

        .resource-settings-dialog h2 {
            font-size: 1.1rem;
            margin: 0 0 1rem;
        }

        .resource-settings-dialog label {
            display: flex;
            flex-direction: column;
            gap: 0.25rem;
            margin-top: 0.75rem;
        }

        .resource-settings-dialog input {
            box-sizing: border-box;
            font: inherit;
            padding: 0.4rem 0.5rem;
            width: 100%;
        }

        .resource-settings-dialog label[hidden] {
            display: none;
        }

        .resource-settings-actions {
            display: flex;
            gap: 0.5rem;
            justify-content: flex-end;
            margin-top: 1.25rem;
        }

        .resource-settings-actions button {
            margin: 0;
        }

        .sidebar-settings {
            color: #6b7280;
            flex: 0 0 auto;
            font-size: 0.9rem;
            padding: 0.25rem 0.45rem !important;
            width: auto !important;
        }

        .sidebar-settings:hover {
            background: #e5e7eb !important;
            color: #111827;
        }

        .resource-create-dialog input {
            box-sizing: border-box;
            font: inherit;
            padding: 0.4rem 0.5rem;
            width: 100%;
        }

        .resource-create-actions {
            display: flex;
            gap: 0.5rem;
            justify-content: flex-end;
            margin-top: 1.25rem;
        }

        .resource-create-actions button {
            margin: 0;
        }

        .sidebar-list button:hover,
        .sidebar-list button.selected {
            background: #e5e7eb;
        }

        .sidebar-list button.selected,
        .sidebar-list a.sidebar-resource-name.selected,
        .sidebar-list li.selected {
            background: #e5e7eb;
            color: #111827;
            font-weight: 600;
        }

        .sidebar-list li {
            align-items: center;
            border-radius: 0.35rem;
            display: flex;
            gap: 0.25rem;
            padding: 0.4rem 0.5rem;
        }

        .sidebar-list li > span {
            flex: 1;
            min-width: 0;
        }

        .sidebar-backdrop {
            background: rgb(0 0 0 / 35%);
            bottom: 0;
            display: none;
            left: 3rem;
            position: fixed;
            right: 0;
            top: 0;
            z-index: 10;
        }

        .sidebar-backdrop.visible {
            display: block;
        }

        .conversation {
            display: flex;
            flex-direction: column;
            gap: 1rem;
            margin-bottom: 1.5rem;
        }

        .history-loading {
            align-items: center;
            color: #6b7280;
            display: flex;
            gap: 0.5rem;
            justify-content: center;
            min-height: 5rem;
        }

        .session-start {
            align-items: center;
            color: #9ca3af;
            display: flex;
            font-size: 0.8rem;
            gap: 0.75rem;
            justify-content: center;
            margin: 0.5rem 0;
        }

        .session-start::before,
        .session-start::after {
            background: #d1d5db;
            content: '';
            flex: 1;
            height: 1px;
        }

        .pending-status {
            align-items: center;
            color: #6b7280;
            display: flex;
            gap: 0.5rem;
            margin-top: 0.75rem;
        }

        .pending-response,
        .pending-response * {
            color: #6b7280 !important;
        }

        .partial-response {
            align-self: flex-start;
            color: #6b7280;
            font-size: 0.9rem;
            max-width: 80%;
            overflow-wrap: anywhere;
        }

        .partial-response summary {
            cursor: pointer;
        }

        .partial-response-content {
            background: #f3f4f6;
            border-left: 3px solid #9ca3af;
            color: #6b7280;
            margin-top: 0.5rem;
            padding: 0.6rem 0.75rem;
            white-space: pre-wrap;
        }

        .workspace-files {
            border: 1px solid #d1d5db;
            border-radius: 0.5rem;
            margin-bottom: 1rem;
            padding: 0.75rem;
        }

        .workspace-files.workspace-drop-target {
            border-color: #2563eb;
            box-shadow: 0 0 0 2px #bfdbfe;
        }

        .workspace-files h2 {
            font-size: 1rem;
            margin: 0 0 0.75rem;
        }

        #workspace-file-path a,
        #workspace-file-path a:visited {
            color: inherit;
            text-decoration: none !important;
        }

        #workspace-file-path a:hover,
        #workspace-file-path a:focus,
        #workspace-view-title a:hover,
        #workspace-view-title a:focus {
            color: #000000;
            text-decoration: underline !important;
        }

        #workspace-view-title a,
        #workspace-view-title a:visited {
            color: inherit;
            text-decoration: none !important;
        }

        .workspace-file-page-mode h2,
        .workspace-file-page-mode .workspace-files-toolbar,
        .workspace-file-page-mode #workspace-file-status,
        .workspace-file-page-mode #workspace-file-list,
        .workspace-file-page-mode #workspace-file-drag-help {
            display: none;
        }

        .workspace-file-page-mode #workspace-file-view-help {
            display: block;
            margin: 0 0 0.75rem;
        }

        .workspace-edit-page-mode {
            display: none;
        }

        .workspace-files-toolbar,
        .workspace-session-target {
            align-items: center;
            display: flex;
            gap: 0.5rem;
            margin-bottom: 0.75rem;
        }

        .workspace-files-toolbar > button[id^="workspace-file-"] {
            font-size: 0;
            line-height: 1;
            min-width: 2.25rem;
            padding-left: 0.55rem;
            padding-right: 0.55rem;
        }

        .workspace-files-toolbar > button[id^="workspace-file-"]::before {
            font-size: 1.15rem;
        }

        #workspace-file-up::before { content: "\2191"; }
        #workspace-file-refresh::before { content: "\21BB"; }
        #workspace-file-copy-selected::before { content: "\29C9"; }
        #workspace-file-move-selected::before { content: "\21AA"; }
        #workspace-file-delete-selected::before { content: "\2715"; }
        #workspace-file-new-directory::before { content: "\1F4C1\002B"; }
        #workspace-file-new-file::before { content: "\1F4C4\002B"; }
        #workspace-file-upload::before { content: "\21E1"; }

        .workspace-session-target { 
            align-items: center;
            display: flex;
            gap: 0.5rem;
            margin-bottom: 0.75rem;
        }

        .workspace-session-target {
            position: relative;
        }

        .workspace-session-target input {
            box-sizing: border-box;
            font: inherit;
            min-width: 0;
            padding: 0.4rem 0.5rem;
            width: 100%;
        }

        .workspace-session-status {
            align-items: center;
            color: #6b7280;
            display: inline-flex;
            flex: 0 0 auto;
            font-size: 0.85rem;
            gap: 0.35rem;
        }

        .workspace-session-status[hidden] {
            display: none;
        }

        .workspace-session-target button {
            flex: 0 0 auto;
            margin: 0;
        }

        .workspace-session-target-menu {
            background: #ffffff;
            border: 1px solid #9ca3af;
            border-radius: 0.35rem;
            box-shadow: 0 0.35rem 0.8rem rgb(0 0 0 / 20%);
            left: 0;
            max-height: 14rem;
            overflow-y: auto;
            position: absolute;
            right: 5rem;
            top: calc(100% - 0.5rem);
            z-index: 6;
        }

        .workspace-session-target-menu[hidden] {
            display: none;
        }

        .workspace-session-option {
            background: transparent;
            border: 0;
            color: #111827;
            cursor: pointer;
            display: block;
            margin: 0;
            padding: 0.4rem 0.55rem;
            text-align: left;
            width: 100%;
        }

        .workspace-session-option:hover {
            background: #dbeafe;
        }

        .workspace-file-list {
            list-style: none;
            margin: 0;
            padding: 0;
        }

        .workspace-file-list li {
            align-items: center;
            border-radius: 0.25rem;
            display: grid;
            gap: 0.5rem;
            grid-template-columns: auto auto minmax(0, 1fr);
            min-height: 2.5rem;
            padding: 0.45rem;
        }

        .workspace-file-list li:nth-child(even) {
            background: color-mix(in srgb, CanvasText 3%, Canvas);
        }

        .workspace-file-list li:hover {
            background: color-mix(in srgb, #2563eb 10%, Canvas);
        }

        .workspace-file-list input {
            flex: 0 0 auto;
        }

        .workspace-file-name {
            align-items: center;
            background: transparent;
            border: 0;
            color: CanvasText;
            cursor: pointer;
            display: inline-flex;
            font-size: 1rem;
            gap: 0.35rem;
            justify-self: start;
            margin: 0;
            min-width: 0;
            overflow-wrap: anywhere;
            padding: 0.15rem 0;
            text-align: left;
            text-decoration: none;
        }

        .workspace-file-rename-input {
            align-self: stretch;
            box-sizing: border-box;
            font: inherit;
            min-width: 0;
            padding: 0.25rem 0.4rem;
            width: 100%;
        }

        .workspace-file-name:hover {
            text-decoration: underline;
        }

        .workspace-file-directory {
            font-weight: 600;
        }

        .workspace-file-menu {
            align-items: center;
            background: transparent;
            border: 0;
            color: #6b7280;
            cursor: pointer;
            display: inline-flex;
            font-size: 1.1rem;
            justify-content: center;
            margin: 0;
            padding: 0.15rem 0.35rem;
        }

        .workspace-file-menu:hover {
            color: CanvasText;
        }

        .workspace-file-actions {
            background: Canvas;
            border: 1px solid #9ca3af;
            border-radius: 0.35rem;
            box-shadow: 0 0.35rem 0.8rem rgb(0 0 0 / 20%);
            display: flex;
            flex-direction: column;
            min-width: 9rem;
            padding: 0.25rem;
            position: absolute;
            z-index: 5;
        }

        .workspace-file-actions[hidden] {
            display: none;
        }

        .workspace-file-actions button {
            align-items: center;
            background: transparent;
            border: 0;
            display: flex;
            gap: 0.55rem;
            margin: 0;
            padding: 0.4rem 0.55rem;
            text-align: left;
            width: 100%;
        }

        .workspace-action-icon {
            display: inline-flex;
            flex: 0 0 1.15rem;
            justify-content: center;
            width: 1.15rem;
        }

        .workspace-action-icon-delete-tree {
            align-items: center;
            border: 1px solid currentColor;
            box-sizing: border-box;
            flex-basis: 0.9rem;
            font-size: 0.7rem;
            height: 0.9rem;
            justify-content: center;
            line-height: 1;
            width: 0.9rem;
        }

        .workspace-file-actions button:hover {
            background: color-mix(in srgb, #2563eb 12%, Canvas);
        }

        .workspace-view-page {
            border: 1px solid #d1d5db;
            border-radius: 0.5rem;
            margin-bottom: 1rem;
            overflow: hidden;
        }

        .workspace-view-page-header {
            align-items: center;
            display: flex;
            gap: 0.75rem;
            justify-content: space-between;
            padding: 0.65rem 0.75rem;
        }

        .workspace-view-content {
            border-top: 1px solid #d1d5db;
            font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
            max-height: 70vh;
            overflow: auto;
            padding: 0.5rem 0;
            user-select: none;
        }

        .workspace-view-content.workspace-markdown-content {
            font-family: system-ui, sans-serif;
            padding: 1rem;
            user-select: text;
        }

        .workspace-markdown-block {
            align-items: start;
            border-radius: 0.25rem;
            cursor: pointer;
            display: grid;
            gap: 0.75rem;
            grid-template-columns: minmax(3.25rem, max-content) minmax(0, 1fr);
            margin: 0 0 0.35rem;
            overflow-wrap: anywhere;
            padding: 0.2rem 0.4rem;
        }

        .workspace-markdown-line-number {
            color: #9ca3af;
            font: 0.75rem/1.5 ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
            padding-top: 0.1rem;
            text-align: right;
            user-select: none;
            white-space: nowrap;
        }

        .workspace-markdown-block-content {
            min-width: 0;
        }

        .workspace-markdown-block:hover {
            background: color-mix(in srgb, #2563eb 8%, Canvas);
        }

        .workspace-markdown-block.selected {
            background: color-mix(in srgb, #2563eb 24%, Canvas);
        }

        .workspace-markdown-block-content > :first-child {
            margin-top: 0;
        }

        .workspace-markdown-block-content > :last-child {
            margin-bottom: 0;
        }

        .workspace-markdown-block table {
            border-collapse: collapse;
            display: block;
            max-width: 100%;
            overflow-x: auto;
            width: max-content;
        }

        .workspace-markdown-block th,
        .workspace-markdown-block td {
            border: 1px solid #9ca3af;
            padding: 0.3rem 0.55rem;
            text-align: left;
        }

        .workspace-markdown-block pre {
            overflow-x: auto;
        }

        .workspace-markdown-block img {
            height: auto;
            max-width: 100%;
        }

        .workspace-markdown-block input[type="checkbox"] {
            margin-right: 0.4rem;
        }

        #workspace-view-edit-content {
            border: 0;
            border-top: 1px solid #d1d5db;
            border-radius: 0;
            box-sizing: border-box;
            font: 0.95rem/1.5 ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
            min-height: 70vh;
            padding: 0.75rem;
            resize: vertical;
            width: 100%;
        }

        .workspace-view-line {
            cursor: pointer;
            display: grid;
            grid-template-columns: 4rem max-content;
            min-width: max-content;
            white-space: pre;
        }

        .workspace-view-line:hover {
            background: color-mix(in srgb, #2563eb 8%, Canvas);
        }

        .workspace-view-line.selected {
            background: color-mix(in srgb, #2563eb 24%, Canvas);
        }

        #workspace-view-edit-content[hidden],
        #workspace-view-save[hidden],
        #workspace-view-cancel[hidden] {
            display: none;
        }

        .workspace-view-line-number {
            color: #9ca3af;
            padding-right: 0.75rem;
            text-align: right;
        }

        .workspace-view-line-text {
            padding-right: 1rem;
        }

        .history-loading[hidden] {
            display: none;
        }

        .message-label-row {
            align-items: center;
            background: Canvas;
            border-top: 1px solid #d1d5db;
            bottom: 0;
            display: flex;
            justify-content: space-between;
            padding: 0.35rem 0;
            position: sticky;
            z-index: 4;
        }

        .session-action-group {
            align-items: center;
            display: flex;
            gap: 0.25rem;
        }

        .session-action-group button,
        .session-more-menu > button {
            align-items: center;
            box-sizing: border-box;
            color: CanvasText;
            display: inline-flex;
            height: 2.25rem;
            justify-content: center;
            margin: 0;
            min-width: 2.25rem;
            padding: 0;
            width: 2.25rem;
        }

        .session-action-group button:hover,
        .session-more-menu > button:hover {
            background: #e5e7eb;
            color: #111827;
        }

        .session-more-menu {
            position: relative;
        }

        .session-more-menu > div {
            background: Canvas;
            border: 1px solid #9ca3af;
            border-radius: 0.35rem;
            bottom: calc(100% + 0.35rem);
            box-shadow: 0 0.35rem 0.8rem rgb(0 0 0 / 20%);
            display: flex;
            flex-direction: column;
            max-width: calc(100vw - 2rem);
            max-height: min(70vh, 32rem);
            min-width: 12rem;
            overflow-x: hidden;
            overflow-y: auto;
            overscroll-behavior: contain;
            padding: 0.25rem;
            position: absolute;
            right: 0;
            z-index: 8;
        }

        .session-more-menu > div[hidden] {
            display: none;
        }

        .session-more-menu > div button {
            align-items: center;
            background: transparent;
            border: 0;
            box-sizing: border-box;
            color: CanvasText;
            display: flex;
            justify-content: flex-start;
            margin: 0;
            min-width: 0;
            padding: 0.45rem 0.6rem;
            text-align: left;
            white-space: nowrap;
            width: 100%;
        }

        .session-more-menu > div button:hover {
            background: #e5e7eb;
        }

        .session-more-menu > div button.session-more-delete {
            color: #b91c1c;
        }

        .session-more-menu > div button.session-more-delete:hover {
            background: #fee2e2;
            color: #991b1b;
        }

        .history-refresh {
            color: CanvasText;
            font-size: 1rem;
            margin: 0;
        }

        .history-refresh:hover {
            color: #111827;
        }

        .message {
            border-radius: 0.75rem;
            max-width: 80%;
            padding: 0.75rem 1rem;
            white-space: pre-wrap;
            overflow-wrap: anywhere;
        }

        .message.user {
            align-self: flex-end;
            background: #dbeafe;
            color: #172554;
        }

        .message.server {
            align-self: flex-start;
            background: #ffffff;
            color: #111827;
        }

        .message.tool-call {
            align-self: flex-start;
            background: #e5e7eb;
            border-left: 3px solid #6b7280;
            color: #1f2937;
            font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
            max-width: 90%;
        }

        .message.tool {
            align-self: flex-start;
            background: #ecfeff;
            border-left: 3px solid #0891b2;
            color: #164e63;
            font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
            max-width: 90%;
        }

        .tool-call {
            background: #e5e7eb;
            border-left: 3px solid #6b7280;
            border-radius: 0.5rem;
            color: #1f2937;
            margin-top: 0.5rem;
            padding: 0.5rem 0.75rem;
        }

        .message-kind {
            color: #155e75;
            font-size: 0.75rem;
            font-weight: 600;
            margin-bottom: 0.35rem;
        }

        .hidden-group {
            align-self: stretch;
            color: #6b7280;
            font-size: 0.85rem;
        }

        .hidden-group summary {
            background: #f3f4f6;
            border-left: 3px solid #9ca3af;
            border-radius: 0.5rem;
            cursor: pointer;
            padding: 0.5rem 0.75rem;
        }

        .hidden-group-items {
            display: flex;
            flex-direction: column;
            gap: 0.75rem;
            margin-top: 0.75rem;
        }

        /* Hidden entries retain their normal role background, but their text
           is muted when the group is expanded. */
        .hidden-entry,
        .hidden-entry * {
            color: #6b7280 !important;
        }

        .hidden-entry {
            border-left: 3px solid #9ca3af;
        }

        .message.user.hidden-entry {
            background: #dbeafe !important;
        }

        .message.server.hidden-entry {
            background: #ffffff !important;
        }

        .message.tool-call.hidden-entry {
            background: #e5e7eb !important;
        }

        .message.tool.hidden-entry {
            background: #ecfeff !important;
        }

        .tool-call summary {
            cursor: pointer;
            font-weight: 600;
        }

        .tool-call pre {
            margin: 0.75rem 0 0;
            white-space: pre-wrap;
            overflow-wrap: anywhere;
        }

        .message-backup {
            border-top: 2px solid #9ca3af;
            margin-top: 0.75rem;
            padding-top: 0.75rem;
        }

        .message-backup-content {
            white-space: pre-wrap;
            overflow-wrap: anywhere;
        }

        .message-backup-content pre {
            margin: 0;
            white-space: pre-wrap;
            overflow-wrap: anywhere;
        }

        .message-footer {
            align-items: center;
            display: flex;
            font-size: 0.8rem;
            gap: 1rem;
            justify-content: flex-end;
            margin-top: 0.75rem;
        }

        .message-time {
            color: #6b7280;
            margin-right: auto;
        }

        .backup-toggle {
            background: transparent;
            border: 0;
            color: #6b7280;
            cursor: pointer;
            font-size: 0.8rem;
            margin: 0;
            padding: 0;
            text-decoration: underline;
        }

        .backup-toggle:hover {
            color: #374151;
        }

        textarea {
            box-sizing: border-box;
            display: block;
            font: inherit;
            min-height: 7rem;
            padding: 0.75rem;
            resize: vertical;
            width: 100%;
        }

        #message {
            font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
            font-variant-ligatures: none;
        }

        button {
            font: inherit;
            margin-top: 0.5rem;
            padding: 0.6rem 1rem;
        }

        button:disabled {
            cursor: default;
            opacity: 0.6;
        }

        .composer-actions {
            align-items: center;
            display: grid;
            gap: 0.5rem;
            grid-template-columns: minmax(0, 1fr) auto;
            margin-top: 1rem;
        }

        .composer-actions-left {
            display: flex;
            flex-wrap: wrap;
            gap: 0.5rem;
            grid-column: 1 / -1;
            grid-row: 2;
            min-width: 0;
        }

        .composer-actions > #send {
            grid-column: 2;
            grid-row: 1;
            justify-self: end;
        }

        .composer-actions button {
            margin-top: 0;
        }

        .composer-panel {
            border: 1px solid #d1d5db;
            border-radius: 0.5rem;
            margin-top: 0.75rem;
            padding: 0.75rem;
        }

        .composer-panel[hidden] {
            display: none;
        }

        .composer-panel h2 {
            font-size: 0.95rem;
            margin: 0 0 0.5rem;
        }

        .composer-panel p {
            color: #6b7280;
            margin: 0;
        }

        .settings-grid {
            display: grid;
            gap: 0.75rem;
            grid-template-columns: repeat(auto-fit, minmax(12rem, 1fr));
        }

        .settings-grid label {
            display: flex;
            flex-direction: column;
            font-size: 0.85rem;
            gap: 0.25rem;
        }

        .settings-grid select {
            box-sizing: border-box;
            font: inherit;
            min-height: 2rem;
            padding: 0.25rem;
            width: 100%;
        }

        .settings-grid select[multiple] {
            min-height: 6rem;
        }

        .settings-actions {
            align-items: center;
            display: flex;
            gap: 0.75rem;
            margin-top: 0.75rem;
        }

        .settings-status {
            color: #6b7280;
            font-size: 0.85rem;
        }

        .files-list {
            list-style: none;
            margin: 0;
            max-height: none;
            padding: 0;
        }

        .files-list:not(.available-resources-list) li {
            align-items: center;
            display: flex;
            gap: 0.5rem;
            padding: 0.2rem 0.45rem;
        }

        .files-list > li:nth-child(even) {
            background: color-mix(in srgb, CanvasText 3%, Canvas);
        }

        .files-list > li:hover {
            background: color-mix(in srgb, #2563eb 10%, Canvas);
        }

        .known-file-path {
            flex: 1;
            font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
            font-size: 0.85rem;
            min-width: 0;
            overflow-wrap: anywhere;
        }

        .available-resource-name {
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
.available-resources-list {
            align-items: center;
            column-gap: 0.75rem;
            display: grid;
            grid-template-columns: minmax(0, 1fr) max-content max-content;
            row-gap: 0.2rem;
        }

        .available-resources-list li {
            display: contents;
        }

        .available-resources-list li > * {
            min-width: 0;
            padding: 0.2rem 0;
        }

        .available-resource-heading {
            color: #6b7280;
            font-size: 0.8rem;
            font-weight: 600;
        }

        .available-resource-name {
            min-width: 0;
        }

        .available-resources-list > li > :nth-child(2),
        .available-resources-list > li > :nth-child(3) {
            justify-self: end;
            text-align: right;
        }

        .available-resource-effects,
        .available-resource-state {
            color: CanvasText;
            white-space: nowrap;
        }

        button.available-resource-state {
            border: 0;
            margin: 0;
            padding: 0.1rem 0;
        }

        button.available-resource-state.busy:disabled {
            cursor: default;
        }

        .available-resource-state.allowed {
            color: CanvasText;
            cursor: default;
        }

        .file-remove {
            flex: 0 0 auto;
            margin: 0;
            padding: 0.1rem 0.45rem;
        }

        .file-add {
            align-items: center;
            display: flex;
            gap: 0.5rem;
            margin-bottom: 0.75rem;
            position: relative;
        }

        .file-add input {
            box-sizing: border-box;
            font: inherit;
            min-width: 0;
            padding: 0.4rem 0.5rem;
            width: 100%;
        }

        .file-completion-menu,
        .resource-completion-menu {
            background: #ffffff;
            border: 1px solid #9ca3af;
            border-radius: 0.35rem;
            box-shadow: 0 0.35rem 0.8rem rgb(0 0 0 / 20%);
            left: 0;
            max-height: 16rem;
            overflow-y: auto;
            position: absolute;
            right: 4.5rem;
            top: calc(100% + 0.2rem);
            z-index: 5;
        }

        .file-completion-menu[hidden],
        .resource-completion-menu[hidden] {
            display: none;
        }

        .completion-field .file-completion-menu {
            right: 0;
        }

        .file-completion-option,
        .resource-completion-option {
            background: transparent;
            border: 0;
            border-radius: 0;
            color: #111827;
            cursor: pointer;
            display: block;
            margin: 0;
            overflow: hidden;
            padding: 0.4rem 0.55rem;
            text-align: left;
            text-overflow: ellipsis;
            white-space: nowrap;
            width: 100%;
        }

        .file-completion-loading {
            align-items: center;
            color: #6b7280;
            display: flex;
            gap: 0.5rem;
            padding: 0.45rem 0.55rem;
        }

        .file-completion-option:hover,
        .file-completion-option.selected,
        .resource-completion-option:hover,
        .resource-completion-option.selected {
            background: #dbeafe;
        }

        .file-add button {
            flex: 0 0 auto;
            margin: 0;
        }

        .resource-pattern-controls {
            margin-bottom: 0.75rem;
        }

        .resource-definition-actions {
            display: flex;
            gap: 0.5rem;
        }

        .resource-definition-actions button {
            margin: 0;
        }

        .files-status {
            align-items: center;
            color: #6b7280;
            display: flex;
            font-size: 0.85rem;
            gap: 0.5rem;
            min-height: 1.2rem;
        }

        .panel-heading {
            align-items: center;
            display: flex;
            justify-content: space-between;
        }

        .resource-refresh {
            font-size: 1rem;
            margin: 0;
            min-width: 2.25rem;
            padding: 0.25rem 0.5rem;
        }

        .credential-created {
            align-items: flex-start;
            display: flex;
            flex-direction: column;
            gap: 0.4rem;
            width: 100%;
        }

        .credential-url {
            align-items: center;
            display: grid;
            gap: 0.5rem;
            grid-template-columns: auto minmax(0, 1fr) auto;
            width: 100%;
        }

        .credential-url a {
            min-width: 0;
            overflow-wrap: anywhere;
        }

        .credential-url button {
            align-items: center;
            display: inline-flex;
            justify-content: center;
            margin: 0;
            padding: 0.25rem 0.45rem;
        }

        .credential-url button svg {
            height: 1em;
            width: 1em;
        }

        .history-actions {
            align-items: center;
            display: flex;
            flex-wrap: wrap;
            gap: 0.75rem;
            justify-content: center;
            margin-bottom: 1rem;
        }

        .history-actions button {
            color: CanvasText;
            margin: 0;
        }

        .history-actions button[hidden] {
            display: none;
        }

        .history-entry-actions {
            align-items: center;
            display: none;
            gap: 0.35rem;
            margin-top: 0.6rem;
        }

        .message.history-entry-selected .history-entry-actions {
            display: flex;
        }

        .history-entry-action {
            color: CanvasText;
            font-size: 0.9rem;
            margin: 0;
            padding: 0.2rem 0.4rem;
        }

        .history-entry-action:hover {
            background: #e5e7eb;
            color: #111827;
        }

        .history-turn-count {
            align-items: center;
            color: #6b7280;
            display: inline-flex;
            font-size: 0.85rem;
            gap: 0.3rem;
        }

        .history-turn-count[hidden] {
            display: none;
        }

        .history-turn-count input {
            box-sizing: border-box;
            font: inherit;
            padding: 0.2rem 0.3rem;
            text-align: center;
            width: 3.5rem;
        }

        .history-stats {
            margin: 0.5rem 0 1rem;
        }

        .history-remaining {
            border-bottom: 1px solid #d1d5db;
            color: #9ca3af;
            display: block;
            font-size: 0.8rem;
            padding: 0.25rem 0 0.55rem;
            text-align: center;
            width: 100%;
        }

        .history-remaining[hidden] {
            display: none;
        }

        .error {
            color: #b91c1c;
            margin-bottom: 1rem;
        }

        @media (max-width: 48rem) {
            body {
                padding: 1rem;
            }

            body::before,
            .sidebar-rail {
                display: none;
            }

            .topbar {
                padding-left: 2.75rem;
            }

            .topbar > #sidebar-toggle {
                left: 0.75rem;
            }

            .sidebar {
                left: 0;
                width: min(18rem, 85vw);
            }

            .sidebar-backdrop {
                left: 0;
            }
        }

        @media (prefers-color-scheme: dark) {
            .message.user {
                background: #1e3a8a;
                color: #dbeafe;
            }

            .message.server {
                background: #ffffff;
                color: #111827;
            }

            .message.tool-call {
                background: #374151;
                border-left-color: #9ca3af;
                color: #f9fafb;
            }

            .message.tool {
                background: #164e63;
                border-left-color: #67e8f9;
                color: #cffafe;
            }

            .hidden-group summary {
                background: #374151;
                border-left-color: #9ca3af;
                color: #d1d5db;
            }

            .message.user.hidden-entry {
                background: #1e3a8a !important;
            }

            .message.server.hidden-entry {
                background: #ffffff !important;
            }

            .message.tool-call.hidden-entry {
                background: #374151 !important;
            }

            .message.tool.hidden-entry {
                background: #164e63 !important;
            }

            .hidden-entry {
                border-left-color: #9ca3af;
                color: #d1d5db !important;
            }

            .file-completion-menu {
                background: #1f2937;
                border-color: #6b7280;
            }

            .file-completion-option {
                color: #f9fafb;
            }

            .file-completion-option:hover,
            .file-completion-option.selected {
                background: #374151;
            }
        }
    </style>
</head>
<body>
    <aside id="sidebar" class="sidebar" aria-label="MAIA navigation" aria-hidden="true">
        <div class="sidebar-header">
            <h2>MAIA</h2>
            <a id="home-link" href="<?= escape($webBasePath) ?>/home">Home</a>
            <button id="sidebar-close" class="sidebar-close" type="button" aria-label="Close sidebar">&#x00D7;</button>
        </div>

        <section class="sidebar-section">
            <h3>Sessions</h3>
            <form id="session-search" class="session-search">
                <label class="visually-hidden" for="session-search-input">Find session</label>
                <input id="session-search-input" type="text" autocomplete="off"
                       placeholder="Session name or regexp">
                <button id="session-search-action" type="submit" aria-label="Search session">🔍</button>
            </form>
            <ul id="session-list" class="sidebar-list" aria-label="MAIA sessions"></ul>
            <p id="session-list-placeholder" class="sidebar-placeholder">Pending sessions...</p>
            <p id="session-loading" class="session-loading" hidden aria-live="polite">
                <span class="spinner" aria-hidden="true"></span>
                Selecting session...
            </p>
        </section>

        <section class="sidebar-section">
            <h3>Workspaces</h3>
            <form id="workspace-search" class="resource-search">
                <label class="visually-hidden" for="workspace-search-input">Find workspace</label>
                <input id="workspace-search-input" type="text" autocomplete="off" placeholder="Workspace name or regexp">
                <button id="workspace-search-action" type="submit" aria-label="Search workspace">🔍</button>
            </form>
            <ul id="workspace-list" class="sidebar-list" aria-label="MAIA workspaces"></ul>
            <p id="workspace-list-placeholder" class="sidebar-placeholder">Pending workspaces...</p>
        </section>

        <section class="sidebar-section">
            <h3>Profiles</h3>
            <form id="profile-search" class="resource-search">
                <label class="visually-hidden" for="profile-search-input">Find profile</label>
                <input id="profile-search-input" type="text" autocomplete="off" placeholder="Profile name or regexp">
                <button id="profile-search-action" type="submit" aria-label="Search profile">🔍</button>
            </form>
            <ul id="profile-list" class="sidebar-list" aria-label="MAIA profiles"></ul>
            <p id="profile-list-placeholder" class="sidebar-placeholder">Pending profiles...</p>
        </section>
    </aside>
    <div id="sidebar-backdrop" class="sidebar-backdrop"></div>

    <dialog id="session-delete-dialog" class="session-delete-dialog">
        <form method="dialog">
            <h2>Delete session?</h2>
            <p id="session-delete-message"></p>
            <div class="session-delete-actions">
                <button type="submit" value="cancel">Cancel</button>
                <button type="submit" value="delete" class="danger">Delete</button>
            </div>
        </form>
    </dialog>

    <dialog id="session-rename-dialog" class="resource-create-dialog">
        <form id="session-rename-form" method="dialog">
            <h2>Rename session</h2>
            <label for="session-rename-name">
                New session name
                <input id="session-rename-name" name="name" type="text"
                       pattern="[A-Za-z0-9_.%+\\-]+" required autocomplete="off">
            </label>
            <p id="session-rename-error" class="error" role="alert" hidden></p>
            <div class="resource-create-actions">
                <button type="submit" value="cancel">Cancel</button>
                <button id="session-rename-submit" type="submit" value="rename">Rename</button>
            </div>
        </form>
    </dialog>

    <dialog id="resource-delete-dialog" class="session-delete-dialog">
        <form method="dialog">
            <h2 id="resource-delete-title">Delete resource?</h2>
            <p id="resource-delete-message"></p>
            <div class="session-delete-actions">
                <button type="submit" value="cancel">Cancel</button>
                <button type="submit" value="delete" class="danger">Delete</button>
            </div>
        </form>
    </dialog>

    <dialog id="resource-settings-dialog" class="resource-settings-dialog">
        <form id="resource-settings-form" method="dialog">
            <h2 id="resource-settings-title">Resource settings</h2>
            <label id="resource-settings-path-label" class="completion-field" for="resource-settings-path" hidden>
                Workspace path relative to MAIA base directory
                <input id="resource-settings-path" name="path" type="text" autocomplete="off" placeholder="project">
                <div id="resource-settings-path-menu" class="file-completion-menu" role="listbox" hidden></div>
            </label>
            <label id="resource-settings-description-label" for="resource-settings-description" hidden>
                Description
                <input id="resource-settings-description" name="description" type="text">
            </label>
            <p id="resource-settings-status" class="settings-status" role="status"></p>
            <div class="resource-settings-actions">
                <button type="submit" value="cancel">Cancel</button>
                <button id="resource-settings-save" type="submit" value="save">Save</button>
            </div>
        </form>
    </dialog>

    <dialog id="resource-create-dialog" class="resource-create-dialog">
        <form id="resource-create-form" method="dialog">
            <h2 id="resource-create-title">Create resource</h2>
            <label for="resource-create-name">
                Name
                <input id="resource-create-name" name="name" type="text" required>
            </label>
            <label id="resource-create-path-label" class="completion-field" for="resource-create-path" hidden>
                Workspace path relative to MAIA home
                <input id="resource-create-path" name="path" type="text" autocomplete="off" placeholder="project">
                <div id="resource-create-path-menu" class="file-completion-menu" role="listbox" hidden></div>
            </label>
            <label id="resource-create-description-label" for="resource-create-description" hidden>
                Description (optional)
                <input id="resource-create-description" name="description" type="text">
            </label>
            <p id="resource-create-error" class="error" role="alert" hidden></p>
            <div class="resource-create-actions">
                <button type="submit" value="cancel">Cancel</button>
                <button id="resource-create-submit" type="submit" value="create">Create</button>
            </div>
        </form>
    </dialog>

    <div class="app">
        <header class="topbar">
            <button id="sidebar-toggle" class="sidebar-toggle" type="button"
                    aria-label="Open sidebar" aria-expanded="false">&#x2630;</button>
<?php if ($sessionWorkspacePage): ?>
            <h1 id="session-title">session: <a class="session-workspace-session-link" href="<?= escape($webBasePath) ?>/session/<?= rawurlencode($initialSessionName) ?>"><?= escape($initialSessionName) ?></a> / workspace</h1>
<?php else: ?>
            <h1 id="session-title"><?= escape($initialTitle) ?></h1>
<?php endif; ?>
<?php if (!$isResourcePage && !$sessionWorkspacePage): ?>
            <button id="session-title-rename" class="session-title-rename" type="button"
                    aria-label="Rename session" title="Rename session"
                    <?= $initialSessionName === 'No session selected' ? 'hidden' : '' ?>>&#x270E;</button>
<?php endif; ?>
            <span id="profile-page-scope" class="settings-status" hidden></span>
            <button id="create-profile" type="button"<?= !$isResourcePage ? ' hidden' : '' ?>>Create profile</button>
            <button id="profile-page-settings" class="sidebar-settings" type="button" hidden
                    aria-label="Profile settings">&#x2699;&#xFE0E;</button>
        </header>

        <div class="history-actions">
            <button id="load-earlier" type="button" hidden title="Load previous turn(s)" aria-label="Load previous turns">&#x2B06;</button>
            <label id="turn-count-control" class="history-turn-count" hidden>
                <input id="turn-count" type="text" inputmode="numeric" maxlength="3" value="1"
                       aria-label="Number of previous turns to load">
                turns
            </label>
            <button id="load-all-history" type="button" hidden title="Load entire history" aria-label="Load entire history">&#x21C8;</button>
	</div>
        <div class="history-stats">
            <span id="history-remaining" class="history-remaining" hidden></span>
        </div>
        <dialog id="history-edit-dialog" class="resource-create-dialog">
            <form id="history-edit-form" method="dialog">
                <h2>Edit history entry</h2>
                <textarea id="history-edit-content" required></textarea>
                <p id="history-edit-error" class="error" role="alert" hidden></p>
                <div class="resource-create-actions">
                    <button type="submit" value="cancel">Cancel</button>
                    <button id="history-edit-submit" type="submit" value="save">Save</button>
                </div>
            </form>
        </dialog>
<?php if ($workspacePageName !== '' || !$isResourcePage): ?>
        <section id="workspace-files" class="workspace-files<?= !$sessionWorkspacePage && !$isResourcePage ? ' composer-panel' : '' ?><?= $initialWorkspacePathType === 'file' ? ' workspace-file-page-mode' : '' ?><?= $workspacePageEdit ? ' workspace-edit-page-mode' : '' ?>"<?= !$sessionWorkspacePage && !$isResourcePage ? ' hidden' : '' ?>>
            <h2 class="workspace-files-heading">Workspace files</h2>
            <div class="workspace-files-toolbar">
                <strong id="workspace-file-path">/</strong>
                <button id="workspace-file-up" type="button" disabled aria-label="Go up" title="Go up">&#8593;</button>
                <button id="workspace-file-refresh" type="button" aria-label="Refresh" title="Refresh">&#8635;</button>
                <button id="workspace-file-copy-selected" type="button" disabled
                        aria-label="Copy selected files" title="Copy selected files">â§</button>
                <button id="workspace-file-move-selected" type="button" disabled
                        aria-label="Move selected files" title="Move selected files">âª</button>
                <button id="workspace-file-delete-selected" type="button" disabled
                        aria-label="Delete selected files" title="Delete selected files">Ã</button>
                <button id="workspace-file-new-directory" type="button" aria-label="Create directory" title="Create directory">📁+</button>
                <button id="workspace-file-new-file" type="button" aria-label="Create file" title="Create file">📄+</button>
                <input id="workspace-file-upload-input" type="file" multiple hidden>
                <button id="workspace-file-upload" type="button" aria-label="Upload files" title="Upload files">⇧</button>
            </div>
            <p id="workspace-file-status" class="settings-status files-status" role="status"><?= $initialWorkspaceName === '' && !$sessionWorkspacePage ? 'This session has no workspace configured.' : '' ?></p>
            <ul id="workspace-file-list" class="workspace-file-list"<?= $initialWorkspacePathType === 'file' ? ' hidden' : '' ?>></ul>
            <p id="workspace-file-drag-help" class="settings-status">Drag a file into a matching session (in another window) to add it to that session, or use the below.</p>
            <p id="workspace-file-view-help" class="settings-status" hidden>Mark lines below to add to a session.</p>
            <div class="workspace-session-target">
<?php if ($sessionWorkspacePage): ?>
                <span id="workspace-session-fixed">Adding to session <?= escape($initialSessionName) ?></span>
<?php else: ?>
                <label class="visually-hidden" for="workspace-session-input">Select a session</label>
                <input id="workspace-session-input" type="text" autocomplete="off" placeholder="Select a session">
                <span id="workspace-session-status" class="workspace-session-status" role="status">
                    <span class="spinner" aria-hidden="true"></span>
                    Loading sessions...
                </span>
                <div id="workspace-session-menu" class="workspace-session-target-menu" role="listbox" hidden></div>
<?php endif; ?>
                <button id="workspace-add-files" type="button" disabled>Add selected</button>
            </div>
        </section>
<?php endif; ?>
        <section id="workspace-file-view" class="workspace-view-page" hidden>
            <div class="workspace-view-page-header">
                <strong id="workspace-view-title"></strong>
                <span>
                    <button id="workspace-view-edit" type="button">Edit</button>
                    <button id="workspace-view-save" type="button" hidden>Save</button>
                    <button id="workspace-view-cancel" type="button" hidden>Cancel</button>
                    <button id="workspace-view-back" type="button">Back to directory</button>
                </span>
            </div>
            <div id="workspace-view-content" class="workspace-view-content" tabindex="0"></div>
            <textarea id="workspace-view-edit-content" hidden spellcheck="false"></textarea>
            <p id="workspace-view-status" class="settings-status" role="status"></p>
        </section>
        <main id="conversation" class="conversation" aria-live="polite"></main>
        <div id="error" class="error" role="alert" hidden></div>

        <form id="message-form">
<?php if (!$isResourcePage): ?>
            <div class="message-label-row">
                <label for="message">Continue in session: <span id="message-session-name"><?= escape($initialSessionName) ?></span></label>
                <div class="session-action-group">
                    <div id="session-more-menu" class="session-more-menu">
                        <button id="session-more-toggle" type="button"
                                aria-label="More session tools" title="More session tools"
                                aria-expanded="false">&#x2630;</button>
                        <div id="session-more-tools" hidden>
                            <button id="history-refresh" class="history-refresh" type="button" aria-label="Refresh history" title="Refresh history">↻ Refresh history</button>
                            <button id="session-action-copy" type="button" aria-label="Copy session" title="Copy session">⧉ Copy session</button>
                            <button id="session-action-rename" type="button" aria-label="Rename session" title="Rename session">&#x270E; Rename session</button>
                            <button id="session-action-settings" type="button" aria-label="Session settings" title="Session settings">&#x2699;&#xFE0E; Session settings</button>
                            <button id="compact-history" type="button" aria-label="Compact history" title="Compact history">&#x224B;&#x2195; Compact history</button>
                            <button id="history-clear" type="button" title="Delete entire history">&#x2327;&#x2195; Delete history</button>
                            <button id="history-hide-all" type="button" title="Hide entire history">&#x2298;&#x2195; Hide history</button>
                            <button id="history-hide-last-turn" type="button" title="Hide last turn">&#x2298; Hide last turn</button>
                            <button id="session-action-delete" class="session-more-delete" type="button" aria-label="Delete session" title="Permanently delete this session">&#x00D7; Delete session</button>
                        </div>
                    </div>
                </div>
            </div>
            <textarea id="message" name="message" required autofocus></textarea>
<?php endif; ?>

            <div class="composer-actions"<?= $pureWorkspaceBrowserPage ? ' hidden' : '' ?>>
                <div class="composer-actions-left">
<?php if ($homePage): ?>
                    <button id="credentials-toggle" type="button"
                            aria-expanded="false">Credentials ▸</button>
<?php endif; ?>
                    <button id="settings-toggle" type="button" hidden
                            aria-expanded="false">&#x2699;&#xFE0E;</button>
                    <button id="files-toggle" type="button"<?= $pureWorkspaceBrowserPage || (!$sessionWorkspacePage && $sessionWorkspaceName === '') ? ' hidden' : '' ?>
                            aria-expanded="false">Files ▸</button>
                    <button id="skills-toggle" type="button"<?= $pureWorkspaceBrowserPage ? ' hidden' : '' ?>
                            aria-expanded="false">Skills ▸</button>
                    <button id="tools-toggle" type="button"<?= $pureWorkspaceBrowserPage ? ' hidden' : '' ?>
                            aria-expanded="false">Tools ▸</button>
<?php if (!$isResourcePage): ?>
                    <button id="workspace-toggle" type="button"<?= !$sessionWorkspacePage && $sessionWorkspaceName === '' ? ' hidden' : '' ?>
                            aria-expanded="false">Workspace ▸</button>
<?php endif; ?>
                </div>
                <button id="send" type="submit" disabled>Send</button>
            </div>

            <dialog id="settings-panel" class="resource-settings-dialog">
                <h2>Session settings</h2>
                <div class="settings-grid">
                    <label for="setting-profile">
                        Profile
                        <select id="setting-profile"></select>
                    </label>
                    <label for="setting-workspace">
                        Workspace
                        <select id="setting-workspace"></select>
                    </label>
                    <label for="setting-filesets">
                        Filesets
                        <select id="setting-filesets" multiple></select>
                    </label>
                    <label for="setting-extra-filesets">
                        Extra send filesets
                        <select id="setting-extra-filesets" multiple></select>
                    </label>
                </div>
                <div class="settings-actions">
                    <button id="settings-save" type="button">Save</button>
                    <button id="settings-cancel" type="button">Cancel</button>
                    <span id="settings-status" class="settings-status" role="status"></span>
                </div>
            </dialog>

            <section id="files-panel" class="composer-panel" hidden>
                <h2 class="panel-heading">Known files <button id="files-refresh" class="resource-refresh" type="button" aria-label="Refresh files" title="Refresh files">&#8635;</button></h2>
                <div class="file-add">
                    <label class="visually-hidden" for="file-path">Add file relative to workspace root</label>
                    <input id="file-path" type="text" autocomplete="off"
                           placeholder="path relative to workspace root">
                    <div id="file-completion-menu" class="file-completion-menu" role="listbox" hidden></div>
                    <button id="file-add-button" type="button">Add</button>
                </div>
                <p id="files-status" class="files-status" role="status"></p>
                <ul id="files-list" class="files-list"></ul>
            </section>

            <section id="tools-panel" class="composer-panel" hidden>
                <h2 class="panel-heading">Tools <button id="tools-refresh" class="resource-refresh" type="button" aria-label="Refresh tools" title="Refresh tools">&#8635;</button></h2>
                <p id="tools-scope" class="settings-status"></p>
                <div class="resource-pattern-controls">
                    <div class="file-add">
                        <label class="visually-hidden" for="tool-pattern">Add tool pattern</label>
                        <input id="tool-pattern" type="text" autocomplete="off"
                               placeholder="tool pattern, e.g. * or *:write">
                        <div id="tool-completion-menu" class="file-completion-menu resource-completion-menu" role="listbox" hidden></div>
                        <button id="tool-pattern-add" type="button">Add</button>
                    </div>
                    <div class="resource-definition-actions">
                        <button id="tool-clear" type="button">Clear</button>
                        <button id="tool-delete" type="button">Delete</button>
                    </div>
                </div>
                <p id="tools-status" class="files-status" role="status"></p>
                <ul id="tool-pattern-list" class="files-list"></ul>
                <details id="available-tools-details">
                    <summary>Available tools</summary>
                    <ul id="available-tools-list" class="files-list available-resources-list">
                        <li class="available-resource-heading">
                            <span class="available-resource-name">Name - Description</span>
                            <span>Effect</span>
                            <span>Allowed</span>
                        </li>
                    </ul>
                </details>
            </section>

            <section id="skills-panel" class="composer-panel" hidden>
                <h2 class="panel-heading">Skills <button id="skills-refresh" class="resource-refresh" type="button" aria-label="Refresh skills" title="Refresh skills">&#8635;</button></h2>
                <p id="skills-scope" class="settings-status"></p>
                <div class="resource-pattern-controls">
                    <div class="file-add">
                        <label class="visually-hidden" for="skill-pattern">Add skill pattern</label>
                        <input id="skill-pattern" type="text" autocomplete="off"
                               placeholder="skill pattern, e.g. *">
                        <div id="skill-completion-menu" class="file-completion-menu resource-completion-menu" role="listbox" hidden></div>
                        <button id="skill-pattern-add" type="button">Add</button>
                    </div>
                    <div class="resource-definition-actions">
                        <button id="skill-clear" type="button">Clear</button>
                        <button id="skill-delete" type="button">Delete</button>
                    </div>
                </div>
                <p id="skills-status" class="files-status" role="status"></p>
                <ul id="skill-pattern-list" class="files-list"></ul>
                <details id="available-skills-details">
                    <summary>Available skills</summary>
                    <ul id="available-skills-list" class="files-list available-resources-list">
                        <li class="available-resource-heading">
                            <span class="available-resource-name">Name - Description</span>
                            <span>Allowed</span>
                            <span>In memory</span>
                        </li>
                    </ul>
                </details>
            </section>
        </form>
<?php if ($homePage): ?>
        <section id="credentials-panel" class="composer-panel credentials-panel" hidden>
            <h2>Credentials</h2>
            <p id="credentials-description" class="settings-status">Credentials used to authenticate access to this MAIA web interface.</p>
            <div class="file-add">
                <label class="visually-hidden" for="credential-name">New credential name (optional)</label>
                <input id="credential-name" type="text" autocomplete="off" placeholder="credential name (optional)">
                <button id="credential-create" type="button">Create</button>
            </div>
            <p id="credentials-status" class="files-status" role="status"></p>
            <ul id="credential-list" class="files-list"></ul>
        </section>
<?php endif; ?>
    </div>

    <script>
        (() => {
            const setInitialLoadingState = () => {
                const states = [
                    ['session-list-placeholder', 'Loading sessions...'],
                    ['workspace-list-placeholder', 'Loading workspaces...'],
                    ['profile-list-placeholder', 'Loading profiles...']
                ];
                for (const [id, text] of states) {
                    const element = document.getElementById(id);
                    if (element) {
                        const spinner = document.createElement('span');
                        spinner.className = 'spinner';
                        spinner.setAttribute('aria-hidden', 'true');
                        const label = document.createElement('span');
                        label.textContent = text;
                        element.replaceChildren(spinner, label);
                    }
                }
            };

            setInitialLoadingState();
        })();
    </script>
    <script src="<?= escape($webBasePath) ?>/marked-18.0.14.umd.js"></script>
    <script src="<?= escape($webBasePath) ?>/purify-3.4.17.min.js"></script>
    <script src="<?= escape($webBasePath) ?>/markdown-viewer.js"></script>
    <script>
        const maiaBasePath = <?= json_encode($webBasePath, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) ?>;
        const initialWorkspaceEntries = <?= json_encode($initialWorkspaceEntries, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) ?>;
        const initialWorkspacePath = <?= json_encode($workspacePagePath, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) ?>;
        const initialWorkspaceFile = <?= json_encode($initialWorkspaceFile, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>;
        const initialWorkspacePathType = <?= json_encode($initialWorkspacePathType) ?>;
        const serverWorkspaceName = <?= json_encode($workspacePageName, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) ?>;
        const serverSessionWorkspaceName = <?= json_encode($sessionWorkspaceName, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) ?>;
        const sessionWorkspacePage = <?= $sessionWorkspacePage ? 'true' : 'false' ?>;
        const pureWorkspaceBrowserPage = <?= $pureWorkspaceBrowserPage ? 'true' : 'false' ?>;
        const maiaUrl = (path) => `${maiaBasePath}${path}`;
        const form = document.getElementById('message-form');
        const input = document.getElementById('message');
        const send = document.getElementById('send');
        const settingsToggle = document.getElementById('settings-toggle');
        const settingsPanel = document.getElementById('settings-panel');
        const settingsSave = document.getElementById('settings-save');
        const settingsCancel = document.getElementById('settings-cancel');
        const settingsStatus = document.getElementById('settings-status');
        const settingProfile = document.getElementById('setting-profile');
        const settingWorkspace = document.getElementById('setting-workspace');
        const settingFilesets = document.getElementById('setting-filesets');
        const settingExtraFilesets = document.getElementById('setting-extra-filesets');
        const filesToggle = document.getElementById('files-toggle');
        const filesPanel = document.getElementById('files-panel');
        const filesStatus = document.getElementById('files-status');
        const filesList = document.getElementById('files-list');
        const filesRefresh = document.getElementById('files-refresh');
        const filePath = document.getElementById('file-path');
        const fileCompletionMenu = document.getElementById('file-completion-menu');
        const fileAddButton = document.getElementById('file-add-button');
        const toolsToggle = document.getElementById('tools-toggle');
        const toolsPanel = document.getElementById('tools-panel');
        const workspaceToggle = document.getElementById('workspace-toggle');
        const toolsRefresh = document.getElementById('tools-refresh');
        const credentialsToggle = document.getElementById('credentials-toggle');
        const credentialsPanel = document.getElementById('credentials-panel');
        const skillsToggle = document.getElementById('skills-toggle');
        const skillsPanel = document.getElementById('skills-panel');
        const skillsRefresh = document.getElementById('skills-refresh');
        const skillsStatus = document.getElementById('skills-status');
        const skillsScope = document.getElementById('skills-scope');
        const skillPattern = document.getElementById('skill-pattern');
        const skillPatternAdd = document.getElementById('skill-pattern-add');
        const skillClear = document.getElementById('skill-clear');
        const skillDelete = document.getElementById('skill-delete');
        const skillPatternList = document.getElementById('skill-pattern-list');
        const availableSkillsList = document.getElementById('available-skills-list');
        const toolsStatus = document.getElementById('tools-status');
        const toolsScope = document.getElementById('tools-scope');
        const toolPattern = document.getElementById('tool-pattern');
        const toolPatternAdd = document.getElementById('tool-pattern-add');
        const profilePageSettings = document.getElementById('profile-page-settings');
        const profilePageScope = document.getElementById('profile-page-scope');
        const createProfileButton = document.getElementById('create-profile');
        const toolClear = document.getElementById('tool-clear');
        const toolDelete = document.getElementById('tool-delete');
        const toolPatternList = document.getElementById('tool-pattern-list');
        const availableToolsDetails = document.getElementById('available-tools-details');
        const availableToolsList = document.getElementById('available-tools-list');
        const historyClear = document.getElementById('history-clear');
        const historyHideLastTurn = document.getElementById('history-hide-last-turn');
        const historyHideAll = document.getElementById('history-hide-all');
        const compactHistory = document.getElementById('compact-history');
        const historyEditDialog = document.getElementById('history-edit-dialog');
        const historyEditForm = document.getElementById('history-edit-form');
        const historyEditContent = document.getElementById('history-edit-content');
        const historyEditError = document.getElementById('history-edit-error');
        const historyEditSubmit = document.getElementById('history-edit-submit');
        const historyRefresh = document.getElementById('history-refresh');
        const sessionActionCopy = document.getElementById('session-action-copy');
        const sessionActionRename = document.getElementById('session-action-rename');
        const sessionActionSettings = document.getElementById('session-action-settings');
        const sessionActionDelete = document.getElementById('session-action-delete');
        const sessionMoreToggle = document.getElementById('session-more-toggle');
        const sessionMoreTools = document.getElementById('session-more-tools');
        const sessionMoreMenu = document.getElementById('session-more-menu');
        const sessionActionMenuContexts = new WeakMap();
        const historyActions = document.querySelector('.history-actions');
        const loadEarlier = document.getElementById('load-earlier');
        const turnCount = document.getElementById('turn-count');
        const turnCountControl = document.getElementById('turn-count-control');
        const historyRemaining = document.getElementById('history-remaining');
        const loadAllHistory = document.getElementById('load-all-history');
        const conversation = document.getElementById('conversation');
        const error = document.getElementById('error');
        const sidebar = document.getElementById('sidebar');
        const sidebarToggle = document.getElementById('sidebar-toggle');
        const sidebarClose = document.getElementById('sidebar-close');
        const sidebarBackdrop = document.getElementById('sidebar-backdrop');
        const sessionTitle = document.getElementById('session-title');
        const sessionTitleRename = document.getElementById('session-title-rename');
        const messageSessionName = document.getElementById('message-session-name');

        function updateBrowserTitle() {
            const pageTitle = sessionTitle?.textContent.trim();
            document.title = pageTitle ? `MAIA - ${pageTitle}` : 'MAIA';
        }

        function renderSessionWorkspaceTitle() {
            if (!sessionTitle || !sessionWorkspacePage || !urlSessionName) {
                return;
            }
            sessionTitle.replaceChildren();
            sessionTitle.append(document.createTextNode('session: '));
            const link = document.createElement('a');
            link.className = 'session-workspace-session-link';
            link.href = maiaUrl(`/session/${encodeURIComponent(urlSessionName)}`);
            link.textContent = urlSessionName;
            sessionTitle.append(link, document.createTextNode(' / workspace'));
            updateBrowserTitle();
        }
        const sessionList = document.getElementById('session-list');
        const sessionListPlaceholder = document.getElementById('session-list-placeholder');
        const sessionLoading = document.getElementById('session-loading');
        const sessionSearch = document.getElementById('session-search');
        const sessionSearchInput = document.getElementById('session-search-input');
        const sessionSearchAction = document.getElementById('session-search-action');
        const sessionCreateAction = document.createElement('button');
        sessionCreateAction.type = 'button';
        sessionCreateAction.textContent = '+';
        sessionCreateAction.setAttribute('aria-label', 'Create session');
        sessionSearchAction.insertAdjacentElement('afterend', sessionCreateAction);
        sessionCreateAction.hidden = true;
        const sessionDeleteDialog = document.getElementById('session-delete-dialog');
        const sessionDeleteMessage = document.getElementById('session-delete-message');
        const sessionRenameDialog = document.getElementById('session-rename-dialog');
        const sessionRenameForm = document.getElementById('session-rename-form');
        const sessionRenameName = document.getElementById('session-rename-name');
        const sessionRenameError = document.getElementById('session-rename-error');
        const sessionRenameSubmit = document.getElementById('session-rename-submit');
        const resourceDeleteDialog = document.getElementById('resource-delete-dialog');
        const resourceDeleteTitle = document.getElementById('resource-delete-title');
        const resourceDeleteMessage = document.getElementById('resource-delete-message');
        const resourceSettingsDialog = document.getElementById('resource-settings-dialog');
        const resourceSettingsForm = document.getElementById('resource-settings-form');
        const resourceSettingsTitle = document.getElementById('resource-settings-title');
        const resourceSettingsPathLabel = document.getElementById('resource-settings-path-label');
        const resourceSettingsPath = document.getElementById('resource-settings-path');
        const resourceSettingsPathMenu = document.getElementById('resource-settings-path-menu');
        const resourceSettingsDescriptionLabel = document.getElementById('resource-settings-description-label');
        const resourceSettingsDescription = document.getElementById('resource-settings-description');
        const resourceSettingsStatus = document.getElementById('resource-settings-status');
        const resourceSettingsSave = document.getElementById('resource-settings-save');
        const workspaceList = document.getElementById('workspace-list');
        const workspaceListPlaceholder = document.getElementById('workspace-list-placeholder');
        const profileList = document.getElementById('profile-list');
        const profileListPlaceholder = document.getElementById('profile-list-placeholder');

        function revealSelectedSidebarItems() {
            const lists = [
                [sessionList, '.session-item > .sidebar-resource-name.selected'],
                [workspaceList, 'li.selected'],
                [profileList, 'li.selected']
            ];
            for (const [list, selector] of lists) {
                const selected = list?.querySelector(selector);
                const row = selected?.closest('li');
                if (!list || !row) {
                    continue;
                }
                const listRect = list.getBoundingClientRect();
                const rowRect = row.getBoundingClientRect();
                if (rowRect.top < listRect.top) {
                    list.scrollTop -= listRect.top - rowRect.top;
                } else if (rowRect.bottom > listRect.bottom) {
                    list.scrollTop += rowRect.bottom - listRect.bottom;
                }
            }
        }

        const workspaceFilesPanel = document.getElementById('workspace-files');
        const composerActions = document.querySelector('.composer-actions');
        if (workspaceFilesPanel && composerActions && !sessionWorkspacePage) {
            composerActions.insertAdjacentElement('afterend', workspaceFilesPanel);
        }
        const workspaceFilePath = document.getElementById('workspace-file-path');
        const workspaceFileUp = document.getElementById('workspace-file-up');
        const workspaceFileRefresh = document.getElementById('workspace-file-refresh');
        const workspaceFileCopySelected = document.getElementById('workspace-file-copy-selected');
        const workspaceFileMoveSelected = document.getElementById('workspace-file-move-selected');
        const workspaceFileDeleteSelected = document.getElementById('workspace-file-delete-selected');
        const workspaceFileNewDirectory = document.getElementById('workspace-file-new-directory');
        const workspaceFileNewFile = document.getElementById('workspace-file-new-file');
        const workspaceFileUpload = document.getElementById('workspace-file-upload');
        const workspaceFileUploadInput = document.getElementById('workspace-file-upload-input');
        const workspaceFileStatus = document.getElementById('workspace-file-status');
        const workspaceFileList = document.getElementById('workspace-file-list');
        const workspaceFileDragHelp = document.getElementById('workspace-file-drag-help');
        const workspaceFileViewHelp = document.getElementById('workspace-file-view-help');
        const workspaceSessionInput = document.getElementById('workspace-session-input');
        const workspaceSessionMenu = document.getElementById('workspace-session-menu');
        const workspaceSessionStatus = document.getElementById('workspace-session-status');
        const workspaceAddFiles = document.getElementById('workspace-add-files');
        const workspaceFileView = document.getElementById('workspace-file-view');
        const workspaceViewTitle = document.getElementById('workspace-view-title');
        const workspaceViewBack = document.getElementById('workspace-view-back');
        const workspaceViewEdit = document.getElementById('workspace-view-edit');
        const workspaceViewSave = document.getElementById('workspace-view-save');
        const workspaceViewCancel = document.getElementById('workspace-view-cancel');
        const workspaceViewContent = document.getElementById('workspace-view-content');
        const workspaceViewEditContent = document.getElementById('workspace-view-edit-content');
        const workspaceViewStatus = document.getElementById('workspace-view-status');
        const workspaceViewReady = [
            workspaceFileView,
            workspaceViewTitle,
            workspaceViewEdit,
            workspaceViewSave,
            workspaceViewCancel,
            workspaceViewContent,
            workspaceViewEditContent,
            workspaceViewStatus
        ].every(Boolean);
        const workspaceSearch = document.getElementById('workspace-search');
        const workspaceSearchInput = document.getElementById('workspace-search-input');
        const workspaceSearchAction = document.getElementById('workspace-search-action');
        const workspaceCreateAction = document.createElement('button');
        workspaceCreateAction.type = 'button';
        workspaceCreateAction.textContent = '+';
        workspaceCreateAction.setAttribute('aria-label', 'Create workspace');
        workspaceSearchAction.insertAdjacentElement('afterend', workspaceCreateAction);
        workspaceCreateAction.hidden = true;
        const profileSearch = document.getElementById('profile-search');
        const profileSearchInput = document.getElementById('profile-search-input');
        const profileSearchAction = document.getElementById('profile-search-action');
        const profileCreateAction = document.createElement('button');
        profileCreateAction.type = 'button';
        profileCreateAction.textContent = '+';
        profileCreateAction.setAttribute('aria-label', 'Create profile');
        profileSearchAction.insertAdjacentElement('afterend', profileCreateAction);
        profileCreateAction.hidden = true;
        const resourceCreateDialog = document.getElementById('resource-create-dialog');
        const resourceCreateForm = document.getElementById('resource-create-form');
        const resourceCreateTitle = document.getElementById('resource-create-title');
        const resourceCreateName = document.getElementById('resource-create-name');
        const resourceCreatePathLabel = document.getElementById('resource-create-path-label');
        const resourceCreatePath = document.getElementById('resource-create-path');
        const resourceCreatePathMenu = document.getElementById('resource-create-path-menu');
        const resourceCreateDescriptionLabel = document.getElementById('resource-create-description-label');
        const resourceCreateDescription = document.getElementById('resource-create-description');
        const resourceCreateError = document.getElementById('resource-create-error');
        const resourceCreateSubmit = document.getElementById('resource-create-submit');
        const credentialName = document.getElementById('credential-name');
        const credentialCreate = document.getElementById('credential-create');
        const credentialsStatus = document.getElementById('credentials-status');
        const credentialList = document.getElementById('credential-list');

        let credentialsLoaded = false;
        let urlSessionName = null;
        let urlWorkspaceName = null;
        let sessionWorkspaceActive = sessionWorkspacePage;
        let selectedSessionWorkspaceName = serverSessionWorkspaceName;
        let urlProfileName = null;
        const maiaPath = maiaBasePath && location.pathname.startsWith(maiaBasePath)
            ? location.pathname.slice(maiaBasePath.length) || '/'
            : location.pathname;
        const urlHomeName = maiaPath === '/home' ? 'home' : null;
        if (maiaPath.startsWith('/workspace/')) {
            try {
                const workspaceUrlPart = maiaPath.slice('/workspace/'.length).split('/');
                urlWorkspaceName = decodeURIComponent(workspaceUrlPart.shift() || '');
            } catch (_) {
                urlWorkspaceName = null;
            }
        }
        if (maiaPath.startsWith('/profile/')) {
            try {
                urlProfileName = decodeURIComponent(maiaPath.slice('/profile/'.length));
            } catch (_) {
                urlProfileName = null;
            }
        }
        if (maiaPath.startsWith('/session/')) {
            try {
                urlSessionName = decodeURIComponent(maiaPath.slice('/session/'.length).split('/')[0]);
            } catch (_) {
                urlSessionName = null;
            }
        }
        if (sessionWorkspacePage && serverWorkspaceName !== '') {
            urlWorkspaceName = serverWorkspaceName;
        }

        const nativeFetch = window.fetch.bind(window);
        window.fetch = (resource, options = {}) => {
            const headers = new Headers(options.headers || {});
            const session = selectedSessionName || urlSessionName;
            if (session && !headers.has('X-MAIA-Session')) {
                headers.set('X-MAIA-Session', session);
            }
            const requestWorkspaceName = urlWorkspaceName || (sessionWorkspaceActive ? selectedSessionWorkspaceName : '');
            if (requestWorkspaceName) {
                headers.set('X-MAIA-Workspace', requestWorkspaceName);
            }
            if (urlProfileName) {
                headers.set('X-MAIA-Profile', urlProfileName);
            }
            if (urlHomeName) {
                headers.set('X-MAIA-Home', 'home');
            }
            if (typeof resource === 'string' && resource.startsWith('/')) {
                resource = maiaUrl(resource);
            }
            return nativeFetch(resource, { ...options, headers });
        };

        const busyButtonStates = new WeakMap();

        function setButtonBusy(button, message = 'Working...') {
            if (!button || busyButtonStates.has(button)) {
                return;
            }
            busyButtonStates.set(button, {
                children: Array.from(button.childNodes, (node) => node.cloneNode(true)),
                disabled: button.disabled,
                ariaLabel: button.getAttribute('aria-label'),
                title: button.getAttribute('title')
            });
            const accessibleName = button.getAttribute('aria-label') ||
                button.getAttribute('title') || button.textContent.trim() || 'Action';
            button.disabled = true;
            button.replaceChildren();
            const spinner = document.createElement('span');
            spinner.className = 'spinner';
            spinner.setAttribute('aria-hidden', 'true');
            const hiddenLabel = document.createElement('span');
            hiddenLabel.className = 'visually-hidden';
            hiddenLabel.textContent = `${accessibleName}: ${message}`;
            button.append(spinner, hiddenLabel);
            button.setAttribute('aria-label', `${accessibleName}: ${message}`);
        }

        function clearButtonBusy(button) {
            const state = button ? busyButtonStates.get(button) : null;
            if (!state) {
                return;
            }
            button.replaceChildren(...state.children);
            button.disabled = state.disabled;
            if (state.ariaLabel === null) {
                button.removeAttribute('aria-label');
            } else {
                button.setAttribute('aria-label', state.ariaLabel);
            }
            if (state.title === null) {
                button.removeAttribute('title');
            } else {
                button.setAttribute('title', state.title);
            }
            busyButtonStates.delete(button);
        }

        function setLoadingStatus(element, message) {
            if (!element) {
                return;
            }
            element.replaceChildren();
            const spinner = document.createElement('span');
            spinner.className = 'spinner';
            spinner.setAttribute('aria-hidden', 'true');
            const text = document.createElement('span');
            text.textContent = message;
            element.append(spinner, text);
            element.hidden = false;
        }

        function clearFloatingMenuStyles(menu) {
            for (const property of ['top', 'left', 'right', 'bottom', 'max-width', 'max-height']) {
                menu.style.removeProperty(property);
            }
        }

        function positionFloatingMenu(menu, toggle) {
            const margin = 8;
            const gap = 6;
            const viewportWidth = document.documentElement.clientWidth || window.innerWidth;
            const viewportHeight = document.documentElement.clientHeight || window.innerHeight;
            const anchor = toggle.getBoundingClientRect();
            const maxMenuHeight = Math.max(1, viewportHeight - 2 * margin);

            menu.style.top = '0px';
            menu.style.left = '0px';
            menu.style.maxWidth = `${Math.max(1, viewportWidth - 2 * margin)}px`;
            menu.style.maxHeight = `${maxMenuHeight}px`;

            const desiredHeight = menu.scrollHeight;
            const spaceAbove = Math.max(0, anchor.top - margin - gap);
            const spaceBelow = Math.max(0, viewportHeight - anchor.bottom - margin - gap);
            let placeAbove;
            if (desiredHeight <= spaceAbove) {
                placeAbove = true;
            } else if (desiredHeight <= spaceBelow) {
                placeAbove = false;
            } else {
                // If neither side alone fits, let the menu overlap the anchor
                // rather than clipping ordinary menu items or forcing a scroll bar.
                placeAbove = spaceAbove > spaceBelow;
            }

            const height = menu.getBoundingClientRect().height;
            const desiredTop = placeAbove ? anchor.top - gap - height : anchor.bottom + gap;
            const top = Math.max(margin, Math.min(desiredTop, viewportHeight - margin - height));
            menu.style.top = `${top}px`;

            const width = Math.min(menu.getBoundingClientRect().width, viewportWidth - 2 * margin);
            const left = Math.max(margin, Math.min(anchor.right - width, viewportWidth - margin - width));
            menu.style.left = `${left}px`;
        }

        function closeSessionActionMenu(menu) {
            menu.hidden = true;
            menu.classList.remove('session-item-actions-menu-floating');
            clearFloatingMenuStyles(menu);
            const context = sessionActionMenuContexts.get(menu);
            if (context) {
                context.parent.appendChild(menu);
                context.toggle.setAttribute('aria-expanded', 'false');
            } else {
                menu.parentElement?.querySelector('.session-item-actions-toggle')
                    ?.setAttribute('aria-expanded', 'false');
            }
        }

        function closeAllSessionActionMenus() {
            document.querySelectorAll('.session-item-actions-menu').forEach(closeSessionActionMenu);
        }

        function closeSessionMoreTools() {
            if (!sessionMoreTools) return;
            sessionMoreTools.hidden = true;
            sessionMoreTools.classList.remove('session-more-tools-floating');
            clearFloatingMenuStyles(sessionMoreTools);
            sessionMoreMenu?.appendChild(sessionMoreTools);
            sessionMoreToggle?.setAttribute('aria-expanded', 'false');
        }

        function repositionFloatingMenus() {
            document.querySelectorAll('.session-item-actions-menu-floating').forEach((menu) => {
                const context = sessionActionMenuContexts.get(menu);
                if (context) positionFloatingMenu(menu, context.toggle);
            });
            if (sessionMoreTools?.classList.contains('session-more-tools-floating')) {
                positionFloatingMenu(sessionMoreTools, sessionMoreToggle);
            }
        }

        window.addEventListener('resize', repositionFloatingMenus);
        document.addEventListener('scroll', repositionFloatingMenus, true);

        function setSidebarOpen(open) {
            if (!open) closeAllSessionActionMenus();
            document.body.classList.toggle('sidebar-open', open);
            sidebar.classList.toggle('open', open);
            sidebarBackdrop.classList.toggle('visible', open);
            sidebar.setAttribute('aria-hidden', String(!open));
            sidebarToggle.setAttribute('aria-expanded', String(open));
            if (open) {
                requestAnimationFrame(revealSelectedSidebarItems);
            }
        }

        sidebarToggle.addEventListener('click', () => setSidebarOpen(true));
        sidebarClose.addEventListener('click', () => setSidebarOpen(false));
        sidebarBackdrop.addEventListener('click', () => setSidebarOpen(false));
        document.addEventListener('keydown', (event) => {
            if (event.key === 'Escape') {
                closeSessionMoreTools();
                closeAllSessionActionMenus();
                setSidebarOpen(false);
            }
        });

        let settingsLoaded = false;
        let filesLoaded = false;
        let toolsLoaded = false;
        let sidebarOptionsLoaded = false;
        let workspaceNames = [];
        let profileNames = [];
        let selectedWorkspaceName = null;
        let selectedProfileName = null;
        let availableToolNames = [];
        let availableSkillNames = [];

        function validResourceName(name) {
            return /^[A-Za-z0-9][A-Za-z0-9_-]*$/.test(name);
        }

        function resourceMatches(names, query) {
            if (query === '') {
                return names;
            }
            try {
                const pattern = new RegExp(query, 'i');
                return names.filter((name) => pattern.test(name));
            } catch (_) {
                return [];
            }
        }

        function createSidebarActionMenu(name, actions) {
            const wrapper = document.createElement('div');
            wrapper.className = 'session-item-actions';

            const toggle = document.createElement('button');
            toggle.type = 'button';
            toggle.className = 'session-item-actions-toggle';
            toggle.textContent = '☰';
            toggle.title = `Actions for ${name}`;
            toggle.setAttribute('aria-label', `Actions for ${name}`);
            toggle.setAttribute('aria-haspopup', 'menu');
            toggle.setAttribute('aria-expanded', 'false');

            const menu = document.createElement('div');
            menu.className = 'session-item-actions-menu';
            menu.setAttribute('role', 'menu');
            menu.hidden = true;

            for (const { button, label } of actions) {
                const icon = button.textContent;
                button.replaceChildren(
                    document.createTextNode(icon),
                    document.createTextNode(` ${label}`)
                );
                button.setAttribute('role', 'menuitem');
                    button.addEventListener('click', () => {
                        closeSessionActionMenu(menu);
                    });
                menu.appendChild(button);
            }

            toggle.addEventListener('click', (event) => {
                event.stopPropagation();
                const expanded = menu.hidden;
                document.querySelectorAll('.session-item-actions-menu').forEach((other) => {
                    other.hidden = true;
                    other.parentElement?.querySelector('.session-item-actions-toggle')
                        ?.setAttribute('aria-expanded', 'false');
                });
                menu.hidden = !expanded;
                toggle.setAttribute('aria-expanded', String(expanded));
            });

            wrapper.append(toggle, menu);
            return wrapper;
        }

        function renderSidebarNames(list, placeholder, names, selected, query = '', type = '') {
            list.replaceChildren();
            const values = resourceMatches(Array.isArray(names) ? names : [], query);
            placeholder.hidden = values.length > 0;
            placeholder.textContent = values.length > 0 ? '' : 'No matches.';

            for (const name of values) {
                const item = document.createElement('li');
                item.classList.toggle('selected', name === selected);

                if (type === 'profile' || type === 'workspace') {
                    const resourceLink = document.createElement('a');
                    const prefix = type === 'profile' ? '/profile/' : '/workspace/';
                    resourceLink.href = maiaUrl(`${prefix}${encodeURIComponent(name)}`);
                    resourceLink.className = 'sidebar-resource-name';
                    resourceLink.textContent = name;
                    resourceLink.addEventListener('click', (event) => {
                        if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) {
                            return;
                        }
                        event.preventDefault();
                        window.location.href = resourceLink.href;
                    });
                    item.appendChild(resourceLink);
                } else {
                    const label = document.createElement('a');
                    label.href = maiaUrl(`/session/${encodeURIComponent(name)}`);
                    label.className = 'sidebar-resource-name';
                    label.textContent = name;
                    label.addEventListener('click', (event) => {
                        if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) {
                            return;
                        }
                        event.preventDefault();
                        selectSession(name);
                    });
                    item.appendChild(label);
                }

                if (type !== '') {
                    const settings = document.createElement('button');
                    settings.type = 'button';
                    settings.className = 'sidebar-settings';
                    settings.textContent = '⚙︎';
                    settings.title = `Settings for ${type} ${name}`;
                    settings.setAttribute('aria-label', `Settings for ${type} ${name}`);
                    settings.addEventListener('click', (event) => {
                        event.stopPropagation();
                        openResourceSettings(type, name);
                    });
                    const remove = document.createElement('button');
                    remove.type = 'button';
                    remove.className = 'session-delete';
                    remove.textContent = 'X';
                    remove.title = `Permanently delete ${type} ${name}`;
                    remove.setAttribute('aria-label', `Permanently delete ${type} ${name}`);
                    remove.addEventListener('click', (event) => {
                        event.stopPropagation();
                        deleteResource(type, name, remove);
                    });
                    item.appendChild(createSidebarActionMenu(`${type} ${name}`, [
                        { button: settings, label: 'Settings' },
                        { button: remove, label: 'Delete' }
                    ]));
                }
                list.appendChild(item);
            }
            if (sidebar.classList.contains('open')) {
                requestAnimationFrame(revealSelectedSidebarItems);
            }
        }

        function updateResourceSearchAction(input, action, names, label, createAction) {
            const query = input.value.trim();
            const exactMatch = names.some((name) => name === query);
            const canCreate = query !== '' && !exactMatch && validResourceName(query);
            action.textContent = '🔍';
            action.setAttribute('aria-label', `Search ${label}`);
            if (createAction) {
                createAction.hidden = !canCreate || (label === 'profile' && !urlWorkspaceName && !urlProfileName && !urlHomeName);
            }
        }

        function updateSessionSearchAction() {
            updateResourceSearchAction(
                sessionSearchInput,
                sessionSearchAction,
                knownSessions.map((session) => session.name),
                'session',
                sessionCreateAction
            );
        }

        function updateSidebarResourceSearch(type) {
            if (type === 'workspace') {
                renderSidebarNames(workspaceList, workspaceListPlaceholder, workspaceNames, selectedWorkspaceName, workspaceSearchInput.value.trim(), 'workspace');
                updateResourceSearchAction(workspaceSearchInput, workspaceSearchAction, workspaceNames, 'workspace', workspaceCreateAction);
            } else {
                renderSidebarNames(profileList, profileListPlaceholder, profileNames, selectedProfileName, profileSearchInput.value.trim(), 'profile');
                updateResourceSearchAction(profileSearchInput, profileSearchAction, profileNames, 'profile', profileCreateAction);
            }
        }

        async function loadSidebarOptions() {
            setLoadingStatus(workspaceListPlaceholder, 'Loading workspaces...');
            setLoadingStatus(profileListPlaceholder, 'Loading profiles...');
            try {
                // Navigation lists are global and must not inherit the
                // selected profile/workspace resource headers.
                const response = await nativeFetch(maiaUrl('/api/session/settings'), {
                    headers: selectedSessionName ? { 'X-MAIA-Session': selectedSessionName } : {}
                });
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || 'Unable to load workspaces and profiles.');
                }

                workspaceNames = Array.isArray(result.workspaces) ? result.workspaces : [];
                profileNames = Array.isArray(result.profiles) ? result.profiles : [];
                selectedWorkspaceName = urlWorkspaceName || result.workspace || null;
                selectedProfileName = urlProfileName || result.profile || null;
                if (!urlWorkspaceName && !urlProfileName && !urlHomeName && selectedSessionName) {
                    selectedSessionWorkspaceName = String(result.workspace ?? '').trim();
                    knownSessions = knownSessions.map((session) => session.name === selectedSessionName
                        ? { ...session, workspace: selectedSessionWorkspaceName }
                        : session);
                    displayedSessions = displayedSessions.map((session) => session.name === selectedSessionName
                        ? { ...session, workspace: selectedSessionWorkspaceName }
                        : session);
                    updateSessionWorkspaceControls();
                }
                renderSidebarNames(
                    workspaceList,
                    workspaceListPlaceholder,
                    workspaceNames,
                    selectedWorkspaceName,
                    workspaceSearchInput.value.trim(),
                    'workspace'
                );
                renderSidebarNames(
                    profileList,
                    profileListPlaceholder,
                    profileNames,
                    selectedProfileName,
                    profileSearchInput.value.trim(),
                    'profile'
                );
                updateSidebarResourceSearch('workspace');
                updateSidebarResourceSearch('profile');
                sidebarOptionsLoaded = true;
                if (sidebar.classList.contains('open')) {
                    requestAnimationFrame(revealSelectedSidebarItems);
                }
            } catch (requestError) {
                workspaceListPlaceholder.hidden = false;
                profileListPlaceholder.hidden = false;
                workspaceListPlaceholder.textContent = `Unable to load workspaces: ${requestError.message || 'unknown error.'}`;
                profileListPlaceholder.textContent = `Unable to load profiles: ${requestError.message || 'unknown error.'}`;
                sidebarOptionsLoaded = false;
            }
        }

        function showCredentialsLoading(message = 'Loading credentials...') {
            if (!credentialsStatus) {
                return;
            }
            credentialsStatus.replaceChildren();
            const spinner = document.createElement('span');
            spinner.className = 'spinner';
            spinner.setAttribute('aria-hidden', 'true');
            const text = document.createElement('span');
            text.textContent = message;
            credentialsStatus.append(spinner, text);
        }

        async function loadCredentials() {
            if (!credentialList || !credentialsStatus) {
                return;
            }
            showCredentialsLoading();
            try {
                const response = await fetch('/api/auth/context');
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || 'Unable to load credentials.');
                }
                credentialList.replaceChildren();
                for (const credential of result.credentials || []) {
                    const item = document.createElement('li');
                    const value = document.createElement('span');
                    value.className = 'known-file-path';
                    const salt = typeof credential.salt === 'string'
                        ? credential.salt
                        : String(credential.identifier || '').split(':')[1] || '';
                    value.textContent = salt === ''
                        ? credential.name
                        : `${credential.name}:${salt.slice(0, 4)}`;
                    value.title = credential.identifier;
                    const remove = document.createElement('button');
                    remove.type = 'button';
                    remove.className = 'file-remove';
                    remove.textContent = 'X';
                    remove.title = `Delete credential ${credential.name}`;
                    remove.setAttribute('aria-label', `Delete credential ${credential.name}`);
                    remove.addEventListener('click', () => deleteCredential(credential, remove));
                    item.append(value, remove);
                    credentialList.appendChild(item);
                }
                credentialsStatus.textContent = result.credentials?.length
                    ? ''
                    : 'No credentials configured.';
                credentialsLoaded = true;
            } catch (requestError) {
                credentialsStatus.textContent = requestError.message || 'Unable to load credentials.';
                credentialsLoaded = false;
            }
        }

        credentialsToggle?.addEventListener('click', async () => {
            const expanded = credentialsPanel.hidden;
            credentialsPanel.hidden = !expanded;
            credentialsToggle.setAttribute('aria-expanded', String(expanded));
            credentialsToggle.textContent = expanded ? 'Credentials \u25BE' : 'Credentials \u25B8';
            if (expanded && !credentialsLoaded) {
                await loadCredentials();
            }
        });

        async function createCredential() {
            const name = credentialName.value.trim();
            if (name !== '' && !/^[A-Za-z0-9_-]+$/.test(name)) {
                credentialsStatus.textContent = 'Use a credential name containing only letters, digits, underscore and hyphen.';
                credentialName.focus();
                return;
            }
            setButtonBusy(credentialCreate, 'Creating credential...');
            credentialName.disabled = true;
            setLoadingStatus(credentialsStatus, 'Creating credential...');
            try {
                const response = await fetch('/api/auth/context', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ action: 'create', name })
                });
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || 'Unable to create credential.');
                }
                credentialName.value = '';
                credentialsLoaded = false;
                await loadCredentials();
                credentialsStatus.replaceChildren();
                const created = result.credential || {};
                const createdName = created.name || (name || 'auto');
                const createdSalt = created.salt || (() => {
                    try {
                        return new URL(result.url).hash.slice(6).split(':')[0];
                    } catch (_) {
                        return '';
                    }
                })();
                const createdMessage = document.createElement('div');
                createdMessage.className = 'credential-created';
                const createdLine = document.createElement('strong');
                createdLine.textContent = `Created ${createdName}:${createdSalt.slice(0, 4)}. `;
                if (result.qrUrl) {
                    const qrLink = document.createElement('a');
                    qrLink.href = result.qrUrl;
                    qrLink.textContent = 'QR code';
                    qrLink.target = '_blank';
                    qrLink.rel = 'noopener noreferrer';
                    createdLine.append(qrLink);
                }
                createdMessage.appendChild(createdLine);
                if (result.url) {
                    const urlLine = document.createElement('div');
                    urlLine.className = 'credential-url';
                    const urlLabel = document.createElement('span');
                    urlLabel.textContent = 'Auth URL:';
                    const link = document.createElement('a');
                    link.href = result.url;
                    link.textContent = result.url;
                    link.target = '_blank';
                    link.rel = 'noopener noreferrer';
                    const copy = document.createElement('button');
                    copy.type = 'button';
                    copy.className = 'copy-button';
                    copy.setAttribute('aria-label', 'Copy authentication URL');
                    copy.title = 'Copy authentication URL';
                    copy.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="M9 9.5A2.5 2.5 0 0 1 11.5 7h7A2.5 2.5 0 0 1 21 9.5v7a2.5 2.5 0 0 1-2.5 2.5h-7A2.5 2.5 0 0 1 9 16.5v-7Z" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M15 7V6.5A2.5 2.5 0 0 0 12.5 4h-7A2.5 2.5 0 0 0 3 6.5v7A2.5 2.5 0 0 0 5.5 16H9" fill="none" stroke="currentColor" stroke-width="1.8"/></svg>';
                    copy.addEventListener('click', async () => {
                        try {
                            await navigator.clipboard.writeText(result.url);
                            copy.setAttribute('aria-label', 'Authentication URL copied');
                            copy.title = 'Copied';
                            window.setTimeout(() => {
                                copy.setAttribute('aria-label', 'Copy authentication URL');
                                copy.title = 'Copy authentication URL';
                            }, 1500);
                        } catch (_) {
                            copy.setAttribute('aria-label', 'Copy failed');
                            copy.title = 'Copy failed';
                        }
                    });
                    urlLine.append(urlLabel, link, copy);
                    createdMessage.appendChild(urlLine);
                }
                const instruction = document.createElement('span');
                instruction.textContent = 'Copy the authentication URL or scan the QR code.';
                createdMessage.appendChild(instruction);
                credentialsStatus.appendChild(createdMessage);
            } catch (requestError) {
                credentialsStatus.textContent = requestError.message || 'Unable to create credential.';
            } finally {
                clearButtonBusy(credentialCreate);
                credentialName.disabled = false;
                credentialName.focus();
            }
        }

        async function deleteCredential(credential, button) {
            if (!window.confirm(`Delete credential '${credential.name}'? Existing links using it will stop working.`)) {
                return;
            }
            setButtonBusy(button, `Deleting ${credential.name}...`);
            setLoadingStatus(credentialsStatus, `Deleting ${credential.name}...`);
            try {
                const response = await fetch('/api/auth/context', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ action: 'delete', identifier: credential.identifier })
                });
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || 'Unable to delete credential.');
                }
                credentialsLoaded = false;
                await loadCredentials();
            } catch (requestError) {
                credentialsStatus.textContent = requestError.message || 'Unable to delete credential.';
            } finally {
                clearButtonBusy(button);
            }
        }

        credentialCreate?.addEventListener('click', createCredential);
        credentialName?.addEventListener('keydown', (event) => {
            if (event.key === 'Enter') {
                event.preventDefault();
                createCredential();
            }
        });

        function showFilesLoading(message = 'Loading files...') {
            filesStatus.replaceChildren();
            const spinner = document.createElement('span');
            spinner.className = 'spinner';
            spinner.setAttribute('aria-hidden', 'true');
            const text = document.createElement('span');
            text.textContent = message;
            filesStatus.append(spinner, text);
        }

        async function loadFiles() {
            showFilesLoading();
            try {
                const response = await fetch('/api/file/list');
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || 'Unable to load known files.');
                }

                const nextFiles = document.createDocumentFragment();
                for (const file of result.files || []) {
                    const item = document.createElement('li');
                    const path = document.createElement('span');
                    path.className = 'known-file-path';
                    path.textContent = file;

                    const remove = document.createElement('button');
                    remove.type = 'button';
                    remove.className = 'file-remove';
                    remove.textContent = 'X';
                    remove.title = `Remove ${file}`;
                    remove.setAttribute('aria-label', `Remove ${file}`);
                    remove.addEventListener('click', () => removeFile(file, remove));

                    item.append(path, remove);
                    nextFiles.appendChild(item);
                }

                // Keep the old list visible until the complete replacement is ready.
                filesList.replaceChildren(nextFiles);
                filesStatus.textContent = result.files?.length ? '' : 'No known files.';
                filesLoaded = true;
            } catch (requestError) {
                // Keep the old list visible so a failed refresh is not destructive.
                filesStatus.textContent = requestError.message || 'Unable to load known files.';
                filesLoaded = false;
            }
        }

        async function removeFile(file, button) {
            setButtonBusy(button, `Removing ${file}...`);
            setLoadingStatus(filesStatus, `Removing ${file}...`);
            try {
                const response = await fetch('/api/file/forget', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'text/plain; charset=utf-8'
                    },
                    body: file
                });
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || 'Unable to remove file.');
                }

                filesLoaded = false;
                await loadFiles();
                filesStatus.textContent = `Removed ${file}.`;
            } catch (requestError) {
                filesStatus.textContent = requestError.message || 'Unable to remove file.';
            } finally {
                clearButtonBusy(button);
            }
        }

        function setSelectOptions(select, values, selectedValues, multiple = false) {
            const selected = new Set(Array.isArray(selectedValues) ? selectedValues : [selectedValues]);
            if (selected.size === 0) {
                selected.add('');
            }
            const options = [''].concat(values || []);
            const unique = [...new Set(options)];
            select.replaceChildren();
            for (const value of unique) {
                const option = document.createElement('option');
                option.value = value;
                option.textContent = value === '' ? '(none)' : value;
                option.selected = selected.has(value);
                select.appendChild(option);
            }
            if (!multiple && selected.size > 0) {
                select.value = selectedValues;
            }
        }

        async function loadSettings() {
            setLoadingStatus(settingsStatus, 'Loading...');
            settingsSave.disabled = true;
            try {
                const response = await fetch('/api/session/settings');
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || 'Unable to load session settings.');
                }

                setSelectOptions(settingProfile, result.profiles, result.profile);
                setSelectOptions(settingWorkspace, result.workspaces, result.workspace);
                setSelectOptions(settingFilesets, result.filesetOptions, result.filesets, true);
                setSelectOptions(settingExtraFilesets, result.filesetOptions, result.extraSendFilesets, true);
                settingsLoaded = true;
                settingsStatus.textContent = '';
            } catch (requestError) {
                settingsStatus.textContent = requestError.message || 'Unable to load settings.';
            } finally {
                settingsSave.disabled = false;
            }
        }

        settingsToggle.addEventListener('click', async () => {
            if (urlProfileName) {
                await openResourceSettings('profile', urlProfileName);
                return;
            }
            if (urlWorkspaceName) {
                await openResourceSettings('workspace', urlWorkspaceName);
                return;
            }
            if (settingsPanel.open) {
                settingsPanel.close();
                return;
            }
            settingsPanel.showModal();
            settingsToggle.setAttribute('aria-expanded', 'true');
            if (!settingsLoaded) {
                await loadSettings();
            }
        });

        settingsCancel.addEventListener('click', () => settingsPanel.close());
        settingsPanel.addEventListener('close', () => {
            settingsToggle.setAttribute('aria-expanded', 'false');
        });

        settingsSave.addEventListener('click', async () => {
            settingsStatus.textContent = 'Saving...';
            setButtonBusy(settingsSave, 'Saving settings...');
            const filesets = Array.from(settingFilesets.selectedOptions).map((option) => option.value).filter(Boolean);
            const extraSendFilesets = Array.from(settingExtraFilesets.selectedOptions).map((option) => option.value).filter(Boolean);

            try {
                const response = await fetch('/api/session/settings', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({
                        profile: settingProfile.value,
                        workspace: settingWorkspace.value,
                        filesets,
                        extraSendFilesets
                    })
                });
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || 'Unable to save session settings.');
                }

                setSelectOptions(settingProfile, result.profiles, result.profile);
                setSelectOptions(settingWorkspace, result.workspaces, result.workspace);
                setSelectOptions(settingFilesets, result.filesetOptions, result.filesets, true);
                setSelectOptions(settingExtraFilesets, result.filesetOptions, result.extraSendFilesets, true);
                if (selectedSessionName) {
                    const workspaceName = String(result.workspace ?? '').trim();
                    knownSessions = knownSessions.map((session) => session.name === selectedSessionName
                        ? { ...session, workspace: workspaceName }
                        : session);
                    displayedSessions = displayedSessions.map((session) => session.name === selectedSessionName
                        ? { ...session, workspace: workspaceName }
                        : session);
                    updateSessionWorkspaceControls();
                }
                settingsStatus.textContent = 'Saved.';
                filesLoaded = false;
                if (!filesPanel.hidden) {
                    await loadFiles();
                }
            } catch (requestError) {
                settingsStatus.textContent = requestError.message || 'Unable to save settings.';
            } finally {
                clearButtonBusy(settingsSave);
            }
        });

        async function refreshFiles() {
            filesRefresh.disabled = true;
            try {
                await loadFiles();
            } finally {
                filesRefresh.disabled = false;
            }
        }

        filesRefresh.addEventListener('click', refreshFiles);

        filesToggle.addEventListener('click', async () => {
            const expanded = filesPanel.hidden;
            filesPanel.hidden = !expanded;
            filesToggle.setAttribute('aria-expanded', String(expanded));
            filesToggle.textContent = expanded ? 'Files \u25BE' : 'Files \u25B8';
            if (expanded && !filesLoaded) {
                await loadFiles();
            }
        });

        function setupWorkspacePathCompletion(input, menu) {
            let candidates = [];
            let query = '';
            let pending = false;
            let timer = null;
            let requestId = 0;

            const render = () => {
                menu.replaceChildren();
                if (candidates.length === 0) {
                    menu.hidden = true;
                    return;
                }
                for (const candidate of candidates) {
                    const option = document.createElement('button');
                    option.type = 'button';
                    option.className = 'file-completion-option';
                    option.textContent = candidate;
                    option.addEventListener('mousedown', (event) => {
                        event.preventDefault();
                        input.value = candidate;
                        menu.hidden = true;
                        refresh();
                        input.focus();
                    });
                    menu.appendChild(option);
                }
                menu.hidden = false;
            };

            const refresh = async () => {
                const value = input.value;
                const currentRequest = ++requestId;
                query = value;
                pending = true;
                try {
                    const response = await fetch(`/api/workspace/complete?path=${encodeURIComponent(value)}`);
                    const result = await response.json();
                    if (currentRequest !== requestId || input.value !== value) {
                        return;
                    }
                    candidates = response.ok && result.ok && Array.isArray(result.candidates)
                        ? result.candidates
                        : [];
                    render();
                } catch (_) {
                    if (currentRequest === requestId) {
                        candidates = [];
                        render();
                    }
                } finally {
                    if (currentRequest === requestId) {
                        pending = false;
                    }
                }
            };

            const complete = () => {
                if (candidates.length === 0 || query !== input.value) {
                    return;
                }
                const completion = candidates.length === 1
                    ? candidates[0]
                    : commonFileCompletionPrefix(candidates);
                if (completion !== '' && completion !== input.value) {
                    input.value = completion;
                    refresh();
                }
                input.focus();
            };

            input.addEventListener('input', () => {
                candidates = [];
                pending = true;
                window.clearTimeout(timer);
                timer = window.setTimeout(refresh, 100);
                menu.hidden = true;
            });
            input.addEventListener('keydown', (event) => {
                if (event.key === 'Tab' && (input.value === '' || pending ||
                    (query === input.value && candidates.length > 0))) {
                    event.preventDefault();
                    window.clearTimeout(timer);
                    const value = input.value;
                    if (query === value && candidates.length > 0) {
                        complete();
                    } else if (pending || value === '') {
                        refresh().then(() => {
                            if (input.value === value) {
                                complete();
                            }
                        });
                    }
                } else if (event.key === 'Escape') {
                    menu.hidden = true;
                }
            });
            input.addEventListener('blur', () => {
                window.setTimeout(() => {
                    menu.hidden = true;
                }, 100);
            });

            return { refresh };
        }

        const resourceCreatePathCompletion = setupWorkspacePathCompletion(
            resourceCreatePath,
            resourceCreatePathMenu
        );
        const resourceSettingsPathCompletion = setupWorkspacePathCompletion(
            resourceSettingsPath,
            resourceSettingsPathMenu
        );

        async function addFile() {
            const path = filePath.value.trim();
            if (path === '') {
                filesStatus.textContent = 'Enter a path relative to the workspace root.';
                filePath.focus();
                return;
            }

            setButtonBusy(fileAddButton, 'Adding file...');
            filePath.disabled = true;
            setLoadingStatus(filesStatus, 'Adding file...');
            try {
                const response = await fetch('/api/file/add', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'text/plain; charset=utf-8'
                    },
                    body: path
                });
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || 'Unable to add file.');
                }

                filePath.value = '';
                filesLoaded = false;
                await loadFiles();
                filesStatus.textContent = `Added ${result.path}.`;
            } catch (requestError) {
                filesStatus.textContent = requestError.message || 'Unable to add file.';
            } finally {
                clearButtonBusy(fileAddButton);
                filePath.disabled = false;
                filePath.focus();
            }
        }

        let fileCompletionCandidates = [];
        let fileCompletionTimer = null;
        let fileCompletionRequest = 0;
        let fileCompletionQuery = '';
        let fileCompletionPending = false;

        function commonFileCompletionPrefix(values) {
            if (values.length === 0) {
                return '';
            }
            let prefix = values[0];
            for (const value of values.slice(1)) {
                let length = 0;
                while (length < prefix.length && length < value.length &&
                       prefix[length] === value[length]) {
                    length++;
                }
                prefix = prefix.slice(0, length);
            }
            return prefix;
        }

        function showFileCompletionLoading() {
            fileCompletionMenu.replaceChildren();
            const status = document.createElement('div');
            status.className = 'file-completion-loading';
            status.setAttribute('role', 'status');
            const spinner = document.createElement('span');
            spinner.className = 'spinner';
            spinner.setAttribute('aria-hidden', 'true');
            const label = document.createElement('span');
            label.textContent = 'Loading files...';
            status.append(spinner, label);
            fileCompletionMenu.appendChild(status);
            fileCompletionMenu.hidden = false;
        }

        function renderFileCompletionMenu() {
            fileCompletionMenu.replaceChildren();
            if (fileCompletionCandidates.length === 0) {
                fileCompletionMenu.hidden = true;
                return;
            }
            for (const candidate of fileCompletionCandidates) {
                const option = document.createElement('button');
                option.type = 'button';
                option.className = 'file-completion-option';
                option.textContent = candidate;
                option.addEventListener('mousedown', (event) => {
                    event.preventDefault();
                    filePath.value = candidate;
                    fileCompletionMenu.hidden = true;
                    updateFileCompletions();
                    filePath.focus();
                });
                fileCompletionMenu.appendChild(option);
            }
            fileCompletionMenu.hidden = false;
        }

        async function updateFileCompletions() {
            const value = filePath.value;
            const requestId = ++fileCompletionRequest;
            fileCompletionQuery = value;
            fileCompletionPending = true;
            showFileCompletionLoading();
            try {
                const response = await fetch(`/api/file/complete?path=${encodeURIComponent(value)}`);
                const result = await response.json();
                if (requestId !== fileCompletionRequest || filePath.value !== value) {
                    return;
                }
                if (!response.ok || !result.ok) {
                    fileCompletionCandidates = [];
                    renderFileCompletionMenu();
                    return;
                }
                fileCompletionCandidates = Array.isArray(result.candidates)
                    ? result.candidates
                    : [];
                renderFileCompletionMenu();
            } catch (_) {
                if (requestId === fileCompletionRequest) {
                    fileCompletionCandidates = [];
                    renderFileCompletionMenu();
                }
            } finally {
                if (requestId === fileCompletionRequest) {
                    fileCompletionPending = false;
                }
            }
        }

        function completeFilePath() {
            if (fileCompletionCandidates.length === 0) {
                return;
            }
            const completion = fileCompletionCandidates.length === 1
                ? fileCompletionCandidates[0]
                : commonFileCompletionPrefix(fileCompletionCandidates);
            if (completion !== '' && completion !== filePath.value) {
                filePath.value = completion;
                updateFileCompletions();
            }
            filePath.focus();
        }

        filePath.addEventListener('input', () => {
            fileCompletionCandidates = [];
            fileCompletionQuery = filePath.value;
            fileCompletionPending = true;
            showFileCompletionLoading();
            window.clearTimeout(fileCompletionTimer);
            fileCompletionTimer = window.setTimeout(updateFileCompletions, 100);
        });
        filePath.addEventListener('keydown', (event) => {
            if (event.key === 'Tab' && (filePath.value === '' || fileCompletionPending ||
                (fileCompletionQuery === filePath.value && fileCompletionCandidates.length > 0))) {
                event.preventDefault();
                window.clearTimeout(fileCompletionTimer);
                const value = filePath.value;
                if (fileCompletionQuery === value && fileCompletionCandidates.length > 0) {
                    completeFilePath();
                } else if (fileCompletionPending || value === '') {
                    updateFileCompletions().then(() => {
                        if (filePath.value === value) {
                            completeFilePath();
                        }
                    });
                }
                return;
            }
            if (event.key === 'Escape') {
                fileCompletionMenu.hidden = true;
            }
            if (event.key === 'Enter') {
                event.preventDefault();
                addFile();
            }
        });
        filePath.addEventListener('blur', () => {
            window.setTimeout(() => {
                fileCompletionMenu.hidden = true;
            }, 100);
        });
        fileAddButton.addEventListener('click', addFile);

        let workspaceRelativePath = initialWorkspacePath;
        let workspaceEntries = Array.isArray(initialWorkspaceEntries) ? initialWorkspaceEntries : [];
        const workspaceSelectedFiles = new Set();
        let workspaceTargetSession = sessionWorkspacePage ? (urlSessionName || '') : '';
        let workspaceViewStart = null;
        let workspaceViewEnd = null;
        let workspaceMarkdownAnchorStart = null;
        let workspaceMarkdownAnchorEnd = null;
        let workspaceViewPointerSelecting = false;
        let workspaceViewPointerDragged = false;

        // A non-root workspace URL may be either a directory or a file. Start
        // in the file-page layout immediately; viewWorkspaceFile() restores
        // the directory layout if the path turns out to be a directory.
        if (workspaceRelativePath !== '' && workspaceFilesPanel && workspaceFileList) {
            workspaceFilesPanel.classList.add('workspace-file-page-mode');
            workspaceFileList.hidden = true;
        }

        function renderWorkspaceSessionMenu() {
            if (!workspaceSessionMenu || !workspaceSessionInput) {
                return;
            }
            const query = workspaceSessionInput.value.trim();
            const sessionCandidates = urlWorkspaceName
                ? knownSessions.filter((session) => session.workspace === urlWorkspaceName)
                : knownSessions;
            const names = sessionCandidates.map((session) => session.name);
            const matches = resourceMatches(names, query);
            workspaceSessionMenu.replaceChildren();
            for (const name of matches) {
                const option = document.createElement('button');
                option.type = 'button';
                option.className = 'workspace-session-option';
                option.textContent = name;
                option.addEventListener('mousedown', (event) => {
                    event.preventDefault();
                    workspaceTargetSession = name;
                    workspaceSessionInput.value = name;
                    workspaceSessionMenu.hidden = true;
                    updateWorkspaceSelectionActions();
                });
                workspaceSessionMenu.appendChild(option);
            }
            workspaceSessionMenu.hidden = matches.length === 0;
        }

        async function workspaceOperation(action, values = {}, triggerButton = null) {
            if (triggerButton) {
                setButtonBusy(triggerButton, `${action[0].toUpperCase()}${action.slice(1)}...`);
            }
            setLoadingStatus(workspaceFileStatus, `${action[0].toUpperCase()}${action.slice(1)}...`);
            try {
                const response = await fetch('/api/workspace/operation', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ action, ...values })
                });
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || `Unable to ${action} workspace path.`);
                }
                await loadWorkspaceFiles(false);
            } finally {
                clearButtonBusy(triggerButton);
            }
        }

        function workspaceEntryActionButton(label, title, handler) {
            const button = document.createElement('button');
            button.type = 'button';
            button.textContent = label;
            button.title = title;
            button.addEventListener('click', (event) => {
                event.stopPropagation();
                handler(button);
            });
            return button;
        }

        function closeWorkspaceFileMenus() {
            document.querySelectorAll('.workspace-file-actions').forEach((menu) => {
                menu.hidden = true;
            });
        }

        const closeWorkspaceMenusUnlessInside = (event) => {
            const target = event.target instanceof Element ? event.target : null;
            if (!target?.closest('.workspace-file-menu, .workspace-file-actions')) {
                closeWorkspaceFileMenus();
            }
        };

        document.addEventListener('pointerdown', closeWorkspaceMenusUnlessInside, true);
        document.addEventListener('click', closeWorkspaceMenusUnlessInside, true);
        document.addEventListener('keydown', (event) => {
            if (event.key === 'Escape') {
                closeWorkspaceFileMenus();
            }
        });
        window.addEventListener('blur', closeWorkspaceFileMenus);

        function workspaceEntryMenu(entry) {
            const wrapper = document.createElement('span');
            wrapper.style.position = 'relative';
            const menuButton = document.createElement('button');
            menuButton.type = 'button';
            menuButton.className = 'workspace-file-menu';
            menuButton.textContent = '☰';
            menuButton.title = `Actions for ${entry.name}`;
            menuButton.setAttribute('aria-label', `Actions for ${entry.name}`);
            const menu = document.createElement('span');
            menu.className = 'workspace-file-actions';
            menu.hidden = true;
            const addAction = (label, handler) => {
                const action = document.createElement('button');
                action.type = 'button';
                const icons = {
                    Rename: '\u270E',
                    Edit: '\u270E',
                    Copy: '\u29C9',
                    Move: '\u21AA',
                    Delete: '\u00D7',
                    Remove: '\u00D7',
                    'Delete tree': '\u2612',
                    Download: '\u21E9'
                };
                const icon = document.createElement('span');
                icon.className = 'workspace-action-icon';
                if (label === 'Delete tree') {
                    icon.classList.add('workspace-action-icon-delete-tree');
                }
                icon.setAttribute('aria-hidden', 'true');
                icon.textContent = icons[label] || '';
                const labelText = document.createElement('span');
                labelText.textContent = label;
                action.append(icon, labelText);
                action.addEventListener('click', (event) => {
                    event.stopPropagation();
                    menu.hidden = true;
                    handler(action);
                });
                menu.appendChild(action);
            };
            addAction('Rename', (button) => {
                workspaceInlineRename(entry, button);
            });
            addAction('Edit', () => {
                window.location.href = `${workspaceLocation(entry.path)}?edit=1`;
            });
            addAction('Copy', async (button) => {
                const destination = window.prompt('Copy to workspace-relative path:', entry.path);
                if (!destination || destination === entry.path) return;
                try { await workspaceOperation('copy', { path: entry.path, destination }, button); }
                catch (requestError) { workspaceFileStatus.textContent = requestError.message || 'Unable to copy path.'; }
            });
            addAction('Move', async (button) => {
                const destination = window.prompt('Move to workspace-relative path:', entry.path);
                if (!destination || destination === entry.path) return;
                try { await workspaceOperation('move', { path: entry.path, destination }, button); }
                catch (requestError) { workspaceFileStatus.textContent = requestError.message || 'Unable to move path.'; }
            });
            if (entry.type === 'directory') {
                if (entry.empty === true) {
                    addAction('Remove', async (button) => {
                        if (!window.confirm(`Remove empty directory ${entry.name}?`)) return;
                        try { await workspaceOperation('remove', { path: entry.path }, button); }
                        catch (requestError) { workspaceFileStatus.textContent = requestError.message || 'Unable to remove directory.'; }
                    });
                }
                addAction('Delete tree', async (button) => {
                    if (!window.confirm(`Delete directory tree ${entry.name} and all of its contents? This cannot be undone.`)) return;
                    try { await workspaceOperation('delete-tree', { path: entry.path }, button); }
                    catch (requestError) { workspaceFileStatus.textContent = requestError.message || 'Unable to delete directory tree.'; }
                });
            } else {
                addAction('Delete', async (button) => {
                    if (!window.confirm(`Delete file ${entry.name}?`)) return;
                    try { await workspaceOperation('delete', { path: entry.path }, button); }
                    catch (requestError) { workspaceFileStatus.textContent = requestError.message || 'Unable to delete file.'; }
                });
            }
            if (entry.type === 'file') {
                addAction('Download', () => {
                    window.location.href = maiaUrl(`/api/workspace/operation?workspace=${encodeURIComponent(urlWorkspaceName)}&path=${encodeURIComponent(entry.path)}&download=1`);
                });
            }
            menuButton.addEventListener('click', (event) => {
                event.stopPropagation();
                document.querySelectorAll('.workspace-file-actions').forEach((other) => {
                    if (other !== menu) other.hidden = true;
                });
                menu.hidden = !menu.hidden;
            });
            wrapper.append(menuButton, menu);
            return wrapper;
        }

        function workspaceInlineRename(entry, menuAction) {
            const row = [...(workspaceFileList?.children || [])].find((candidate) => candidate.dataset.path === entry.path);
            const link = row?.querySelector('.workspace-file-name');
            if (!row || !link || row.querySelector('.workspace-file-rename-input')) {
                return;
            }
            const input = document.createElement('input');
            input.className = 'workspace-file-rename-input';
            input.type = 'text';
            input.value = entry.name;
            input.setAttribute('aria-label', `New name for ${entry.name}`);
            link.replaceWith(input);
            input.focus();
            input.select();
            let finished = false;
            const restore = () => {
                if (finished) return;
                finished = true;
                input.replaceWith(link);
            };
            const save = async () => {
                if (finished) return;
                const name = input.value.trim();
                if (name === '' || name === entry.name || name.includes('/') || name === '.' || name === '..') {
                    restore();
                    return;
                }
                finished = true;
                input.disabled = true;
                try {
                    await workspaceOperation('rename', { path: entry.path, name }, menuAction);
                } catch (requestError) {
                    workspaceFileStatus.textContent = requestError.message || 'Unable to rename path.';
                    input.disabled = false;
                    finished = false;
                    input.focus();
                    input.select();
                }
            };
            input.addEventListener('keydown', (event) => {
                if (event.key === 'Enter') {
                    event.preventDefault();
                    save();
                } else if (event.key === 'Escape') {
                    event.preventDefault();
                    restore();
                }
            });
            input.addEventListener('blur', () => {
                if (!finished) restore();
            });
        }

        function updateWorkspaceSelectionActions() {
            const binaryFile = workspaceFileView?.dataset.binary === '1';
            const hasSelection = binaryFile || workspaceSelectedFiles.size > 0 || (workspaceViewStart !== null && workspaceViewEnd !== null);
            if (workspaceAddFiles) {
                workspaceAddFiles.disabled = !hasSelection || workspaceTargetSession === '';
            }
            if (workspaceFileCopySelected) workspaceFileCopySelected.disabled = !hasSelection;
            if (workspaceFileMoveSelected) workspaceFileMoveSelected.disabled = !hasSelection;
            if (workspaceFileDeleteSelected) workspaceFileDeleteSelected.disabled = !hasSelection;
        }

        async function operateOnSelectedWorkspaceFiles(action, triggerButton = null) {
            const paths = [...workspaceSelectedFiles];
            if (paths.length === 0) return;
            if (action === 'delete' && !window.confirm(`Delete ${paths.length} selected file${paths.length === 1 ? '' : 's'}?`)) return;
            let destination = '';
            if (action === 'copy' || action === 'move') {
                destination = window.prompt(`${action === 'copy' ? 'Copy' : 'Move'} selected files to directory:`, workspaceRelativePath);
                if (destination === null) return;
                destination = destination.trim();
            }
            setButtonBusy(triggerButton, `${action[0].toUpperCase()}${action.slice(1)} selected files...`);
            try {
                for (const path of paths) {
                    const name = path.split('/').pop();
                    await workspaceOperation(action, action === 'delete'
                        ? { path }
                        : { path, destination: `${destination ? `${destination.replace(/\\\\+$/, '')}/` : ''}${name}` });
                }
                workspaceSelectedFiles.clear();
                updateWorkspaceSelectionActions();
                renderWorkspaceEntries();
            } catch (requestError) {
                workspaceFileStatus.textContent = requestError.message || `Unable to ${action} selected files.`;
            } finally {
                clearButtonBusy(triggerButton);
            }
        }

        function renderWorkspaceEntries() {
            if (!workspaceFileList) {
                return;
            }
            workspaceFileList.replaceChildren();
            for (const entry of workspaceEntries) {
                const item = document.createElement('li');
                item.dataset.path = entry.path;
                if (entry.type === 'file') {
                    item.draggable = true;
                    item.addEventListener('dragstart', (event) => {
                        const paths = workspaceSelectedFiles.has(entry.path)
                            ? [...workspaceSelectedFiles]
                            : [entry.path];
                        event.dataTransfer?.setData(
                            'application/x-maia-workspace-files',
                            JSON.stringify(paths)
                        );
                        event.dataTransfer?.setData('application/x-maia-workspace-file', entry.path);
                        event.dataTransfer?.setData('text/plain', paths.join('\n'));
                        if (event.dataTransfer) {
                            event.dataTransfer.effectAllowed = 'copy';
                            const downloadUrl = new URL(
                                maiaUrl(`/api/workspace/operation?workspace=${encodeURIComponent(urlWorkspaceName)}&path=${encodeURIComponent(entry.path)}&download=1`),
                                window.location.href
                            ).href;
                            event.dataTransfer.setData(
                                'DownloadURL',
                                `application/octet-stream:${entry.name}:${downloadUrl}`
                            );
                            event.dataTransfer.setData('text/uri-list', downloadUrl);
                        }
                    });
                    const checkbox = document.createElement('input');
                    checkbox.type = 'checkbox';
                    checkbox.checked = workspaceSelectedFiles.has(entry.path);
                    checkbox.addEventListener('change', () => {
                        if (checkbox.checked) {
                            workspaceSelectedFiles.add(entry.path);
                        } else {
                            workspaceSelectedFiles.delete(entry.path);
                        }
                        updateWorkspaceSelectionActions();
                    });
                    item.appendChild(checkbox);
                }
                const name = document.createElement('button');
                name.type = 'button';
                name.className = `workspace-file-name${entry.type === 'directory' ? ' workspace-file-directory' : ''}`;
                name.textContent = `${entry.type === 'directory' ? '📁 ' : '📄 '}${entry.name}`;
                if (entry.type === 'directory') {
                    name.addEventListener('click', () => {
                        workspaceRelativePath = entry.path;
                        loadWorkspaceFiles();
                    });
                } else {
                    name.disabled = true;
                }
                const menu = workspaceEntryMenu(entry);
                const link = document.createElement('a');
                link.className = `workspace-file-name${entry.type === 'directory' ? ' workspace-file-directory' : ''}`;
                link.href = workspaceLocation(entry.path);
                link.innerHTML = `<span aria-hidden="true">${entry.type === 'directory' ? '📁' : '📄'}</span>`;
                link.appendChild(document.createTextNode(` ${entry.name}`));
                item.replaceChildren(...(entry.type === 'file' ? [item.querySelector('input')] : []), menu, link);
                workspaceFileList.appendChild(item);
            }
            if (workspaceEntries.length === 0) {
                const item = document.createElement('li');
                item.textContent = 'No files or directories.';
                workspaceFileList.appendChild(item);
            }
        }

        function renderWorkspaceBreadcrumb(container, path, onClick = null) {
            if (!container) {
                return;
            }
            container.replaceChildren();
            const addLink = (label, target) => {
                const link = document.createElement('a');
                link.href = workspaceLocation(target);
                link.textContent = label;
                if (onClick) {
                    link.addEventListener('click', (event) => onClick(event, target));
                }
                container.appendChild(link);
            };

            addLink('/', '');
            let current = '';
            for (const [index, part] of path.split('/').filter(Boolean).entries()) {
                current = current === '' ? part : `${current}/${part}`;
                container.appendChild(document.createTextNode(' '));
                addLink(`${part}${index < path.split('/').filter(Boolean).length - 1 ? '/' : ''}`, current);
            }
        }

        function renderWorkspaceViewTitle(path) {
            renderWorkspaceBreadcrumb(workspaceViewTitle, path);
        }

        function normalizeMarkdownWorkspacePath(sourcePath, targetPath) {
            let decoded;
            try {
                decoded = decodeURIComponent(targetPath);
            } catch (_) {
                return null;
            }
            decoded = decoded.replace(/\\/g, '/');
            if (decoded === '') return sourcePath;
            const parts = decoded.startsWith('/')
                ? []
                : sourcePath.split('/').filter(Boolean).slice(0, -1);
            for (const part of decoded.split('/')) {
                if (part === '' || part === '.') continue;
                if (part === '..') {
                    if (parts.length === 0) return null;
                    parts.pop();
                } else {
                    parts.push(part);
                }
            }
            return parts.join('/');
        }

        function resolveMarkdownDestination(sourcePath, rawDestination) {
            const value = String(rawDestination || '').trim();
            if (value === '') return { kind: 'workspace', path: sourcePath, suffix: '' };
            if (value.startsWith('//')) return { kind: 'external', url: `https:${value}` };
            const scheme = value.match(/^([a-z][a-z0-9+.-]*):/i);
            if (scheme) {
                const protocol = scheme[1].toLowerCase();
                if (!['http', 'https', 'mailto', 'tel'].includes(protocol)) return null;
                try {
                    const url = new URL(value);
                    return { kind: 'external', url: url.href };
                } catch (_) {
                    return null;
                }
            }
            const suffixAt = value.search(/[?#]/);
            const rawPath = suffixAt < 0 ? value : value.slice(0, suffixAt);
            const suffix = suffixAt < 0 ? '' : value.slice(suffixAt);
            const path = normalizeMarkdownWorkspacePath(sourcePath, rawPath);
            return path === null ? null : { kind: 'workspace', path, suffix };
        }

        function renderMarkdownWorkspaceFile(content, path) {
            if (typeof window.maiaRenderWorkspaceMarkdown !== 'function') {
                throw new Error('The Markdown viewer could not be loaded.');
            }
            workspaceViewContent.classList.add('workspace-markdown-content');
            workspaceViewContent.replaceChildren(window.maiaRenderWorkspaceMarkdown(content));

            for (const link of workspaceViewContent.querySelectorAll('a[href]')) {
                const destination = resolveMarkdownDestination(path, link.getAttribute('href'));
                if (!destination) {
                    link.removeAttribute('href');
                    continue;
                }
                if (destination.kind === 'external') {
                    link.href = destination.url;
                    if (/^https?:/i.test(destination.url)) {
                        link.target = '_blank';
                        link.rel = 'noopener noreferrer';
                    }
                } else {
                    link.href = `${workspaceLocation(destination.path)}${destination.suffix}`;
                }
            }

            for (const image of workspaceViewContent.querySelectorAll('img[src]')) {
                const destination = resolveMarkdownDestination(path, image.getAttribute('src'));
                if (!destination) {
                    image.removeAttribute('src');
                    continue;
                }
                image.loading = 'lazy';
                if (destination.kind === 'external') {
                    if (!/^https?:/i.test(destination.url)) {
                        image.removeAttribute('src');
                        continue;
                    }
                    image.referrerPolicy = 'no-referrer';
                    image.src = destination.url;
                } else {
                    image.src = maiaUrl(`/api/workspace/operation?workspace=${encodeURIComponent(urlWorkspaceName)}&path=${encodeURIComponent(destination.path)}&raw=1`);
                }
            }

            workspaceViewContent.querySelectorAll('.workspace-markdown-block').forEach((block) => {
                const selectBlock = (extend = false) => {
                    const blockStart = Number(block.dataset.lineStart);
                    const blockEnd = Number(block.dataset.lineEnd);
                    if (!Number.isInteger(blockStart) || !Number.isInteger(blockEnd)) return;
                    if (extend && workspaceMarkdownAnchorStart !== null) {
                        if (blockStart < workspaceMarkdownAnchorStart) {
                            workspaceViewStart = blockStart;
                            workspaceViewEnd = workspaceMarkdownAnchorEnd;
                        } else {
                            workspaceViewStart = workspaceMarkdownAnchorStart;
                            workspaceViewEnd = blockEnd;
                        }
                    } else {
                        workspaceMarkdownAnchorStart = blockStart;
                        workspaceMarkdownAnchorEnd = blockEnd;
                        workspaceViewStart = blockStart;
                        workspaceViewEnd = blockEnd;
                    }
                    const first = Math.min(workspaceViewStart, workspaceViewEnd);
                    const last = Math.max(workspaceViewStart, workspaceViewEnd);
                    workspaceViewContent.querySelectorAll('.workspace-markdown-block').forEach((candidate) => {
                        const start = Number(candidate.dataset.lineStart);
                        const end = Number(candidate.dataset.lineEnd);
                        candidate.classList.toggle('selected', start <= last && end >= first);
                    });
                    const selectionLabel = `Selected source lines: ${first}-${last}`;
                    if (workspaceFileViewHelp) {
                        workspaceFileViewHelp.textContent = selectionLabel;
                    }
                    workspaceViewStatus.textContent = selectionLabel;
                    updateWorkspaceSelectionActions();
                };
                block.addEventListener('pointerdown', (event) => {
                    if (event.target.closest('a, button, input')) return;
                    event.preventDefault();
                    workspaceViewPointerSelecting = true;
                    workspaceViewPointerDragged = false;
                    selectBlock(event.shiftKey);
                });
                block.addEventListener('pointerenter', () => {
                    if (workspaceViewPointerSelecting) {
                        workspaceViewPointerDragged = true;
                        selectBlock(true);
                    }
                });
                block.addEventListener('pointerup', () => {
                    workspaceViewPointerSelecting = false;
                });
                block.addEventListener('click', (event) => {
                    if (event.target.closest('a, button, input')) return;
                    if (!event.shiftKey && !workspaceViewPointerDragged) selectBlock(false);
                    workspaceViewPointerSelecting = false;
                    workspaceViewPointerDragged = false;
                });
            });
        }

        async function viewWorkspaceFile(entry, editMode = false, triggerButton = null) {
            renderWorkspaceViewTitle(entry.path);
            workspaceViewContent.replaceChildren();
            workspaceViewContent.classList.remove('workspace-markdown-content');
            workspaceViewEditContent.value = '';
            workspaceViewStatus.textContent = '';
            workspaceFileView.dataset.binary = '0';
            if (workspaceAddFiles) workspaceAddFiles.textContent = 'Add selected';
            workspaceViewStart = null;
            workspaceViewEnd = null;
            workspaceMarkdownAnchorStart = null;
            workspaceMarkdownAnchorEnd = null;
            workspaceViewPointerSelecting = false;
            workspaceViewPointerDragged = false;
            if (workspaceFileViewHelp) {
                workspaceFileViewHelp.textContent = 'Mark lines below to add to a session.';
            }
            updateWorkspaceSelectionActions();
            try {
                let result;
                if (initialWorkspaceFile && initialWorkspaceFile.path === entry.path) {
                    result = initialWorkspaceFile;
                } else {
                    setLoadingStatus(workspaceViewStatus, 'Loading file...');
                    if (triggerButton) setButtonBusy(triggerButton, 'Loading file...');
                    const response = await fetch(`/api/workspace/operation?view=1&path=${encodeURIComponent(entry.path)}`);
                    result = await response.json();
                    if (!response.ok || !result.ok) {
                        workspaceViewStatus.textContent = result.error || 'Unable to view file.';
                        if (workspaceFileView) {
                            workspaceFileView.hidden = true;
                        }
                        workspaceFilesPanel?.classList.remove('workspace-file-page-mode', 'workspace-edit-page-mode');
                        if (workspaceFileList) {
                            workspaceFileList.hidden = false;
                        }
                        return false;
                    }
                }
                workspaceFileView.dataset.path = entry.path;
                workspaceFileView.dataset.editing = editMode ? '1' : '0';
                workspaceViewEdit.hidden = editMode || result.kind === 'binary';
                workspaceViewSave.hidden = !editMode || result.kind === 'binary';
                workspaceViewCancel.hidden = !editMode || result.kind === 'binary';
                workspaceViewContent.hidden = editMode;
                workspaceViewEditContent.hidden = !editMode;
                if (result.kind === 'binary') {
                    workspaceFileView.dataset.binary = '1';
                    if (workspaceAddFiles) workspaceAddFiles.textContent = 'Add file';
                    if (workspaceFileViewHelp) {
                        workspaceFileViewHelp.hidden = false;
                        workspaceFileViewHelp.textContent = 'Add this file to the selected session.';
                    }
                    workspaceViewContent.replaceChildren();
                    const rawUrl = maiaUrl(`/api/workspace/operation?workspace=${encodeURIComponent(urlWorkspaceName)}&path=${encodeURIComponent(entry.path)}&raw=1`);
                    let preview;
                    if (result.mime?.startsWith('image/')) {
                        preview = document.createElement('img');
                        preview.alt = entry.name;
                        preview.style.maxWidth = '100%';
                    } else if (result.mime?.startsWith('audio/')) {
                        preview = document.createElement('audio');
                        preview.controls = true;
                    } else if (result.mime?.startsWith('video/')) {
                        preview = document.createElement('video');
                        preview.controls = true;
                        preview.style.maxWidth = '100%';
                    } else if (result.mime === 'application/pdf') {
                        preview = document.createElement('iframe');
                        preview.title = entry.name;
                        preview.style.height = '70vh';
                        preview.style.width = '100%';
                    }
                    if (preview) {
                        preview.src = rawUrl;
                        workspaceViewContent.appendChild(preview);
                    } else {
                        const download = document.createElement('a');
                        download.href = rawUrl;
                        download.textContent = `Download ${entry.name} (${result.mime || 'binary file'})`;
                        workspaceViewContent.appendChild(download);
                    }
                    workspaceViewContent.hidden = false;
                    workspaceViewEditContent.hidden = true;
                    workspaceViewStatus.textContent = result.mime || 'Binary file';
                } else {
                    const content = String(result.content ?? '');
                    if (editMode) {
                        workspaceViewContent.classList.remove('workspace-markdown-content');
                        workspaceViewEditContent.value = content;
                        workspaceViewEditContent.focus();
                    } else if (/\.(?:md|markdown)$/i.test(entry.path)) {
                        try {
                            renderMarkdownWorkspaceFile(content, entry.path);
                            workspaceViewStatus.textContent = 'Click a block, or drag across blocks, to select their source lines.';
                            if (workspaceFileViewHelp) {
                                workspaceFileViewHelp.hidden = false;
                                workspaceFileViewHelp.textContent = 'Select blocks below to add their source lines to a session.';
                            }
                        } catch (markdownError) {
                            // If a local renderer asset fails to load, still show
                            // the file safely as plain text rather than a blank view.
                            workspaceViewContent.classList.remove('workspace-markdown-content');
                            workspaceViewContent.textContent = content;
                            workspaceViewStatus.textContent = `Markdown preview unavailable: ${markdownError.message || 'rendering failed.'}`;
                            if (workspaceFileViewHelp) {
                                workspaceFileViewHelp.hidden = false;
                                workspaceFileViewHelp.textContent = 'Showing source text because Markdown preview is unavailable.';
                            }
                        }
                    } else {
                        workspaceViewContent.classList.remove('workspace-markdown-content');
                        // Split on actual Unix, Windows, or classic Mac line endings.
                        // Keeping empty elements is important: blank lines have line
                        // numbers too.
                        const lines = content.split(/\r\n|\n|\r/);
                    const selectLineRange = (lineNumber, extend = false) => {
                        if (extend && workspaceViewStart !== null) {
                            workspaceViewEnd = lineNumber;
                        } else {
                            workspaceViewStart = lineNumber;
                            workspaceViewEnd = lineNumber;
                        }
                        const first = Math.min(workspaceViewStart, workspaceViewEnd);
                        const last = Math.max(workspaceViewStart, workspaceViewEnd);
                        workspaceViewContent.querySelectorAll('.workspace-view-line').forEach((candidate) => {
                            const value = Number(candidate.dataset.line);
                            candidate.classList.toggle('selected', value >= first && value <= last);
                        });
                        if (workspaceFileViewHelp) {
                            workspaceFileViewHelp.textContent = `Marked lines: ${first}-${last}`;
                        }
                        updateWorkspaceSelectionActions();
                    };
                    lines.forEach((line, index) => {
                        const row = document.createElement('div');
                        row.className = 'workspace-view-line';
                        row.dataset.line = String(index + 1);
                        const number = document.createElement('span');
                        number.className = 'workspace-view-line-number';
                        number.textContent = String(index + 1);
                        const text = document.createElement('span');
                        text.className = 'workspace-view-line-text';
                        text.textContent = line;
                        row.append(number, text);
                        row.addEventListener('pointerdown', (event) => {
                            event.preventDefault();
                            workspaceViewPointerSelecting = true;
                            workspaceViewPointerDragged = false;
                            selectLineRange(Number(row.dataset.line), event.shiftKey);
                        });
                        row.addEventListener('pointerenter', () => {
                            if (workspaceViewPointerSelecting) {
                                workspaceViewPointerDragged = true;
                                selectLineRange(Number(row.dataset.line), true);
                            }
                        });
                        row.addEventListener('pointerup', () => {
                            workspaceViewPointerSelecting = false;
                        });
                        row.addEventListener('click', (event) => {
                            if (!event.shiftKey && !workspaceViewPointerDragged) {
                                selectLineRange(Number(row.dataset.line));
                            }
                            workspaceViewPointerSelecting = false;
                            workspaceViewPointerDragged = false;
                        });
                        workspaceViewContent.appendChild(row);
                    });
                        workspaceViewStatus.textContent = '';
                        if (workspaceFileViewHelp) {
                            workspaceFileViewHelp.hidden = false;
                            workspaceFileViewHelp.textContent = 'Mark lines below to add to a session.';
                        }
                    }
                }
                updateWorkspaceSelectionActions();
                if (workspaceFileView) {
                    workspaceFileView.hidden = false;
                }
                if (workspaceFilesPanel) {
                    workspaceFilesPanel.hidden = editMode;
                    workspaceFilesPanel.classList.toggle('workspace-edit-page-mode', editMode);
                    workspaceFilesPanel.classList.add('workspace-file-page-mode');
                }
                if (workspaceFileList) {
                    workspaceFileList.hidden = true;
                }
                workspaceFileView.scrollIntoView({ block: 'start' });
                return true;
            } catch (requestError) {
                workspaceViewStatus.textContent = requestError.message || 'Unable to view file.';
                return false;
            } finally {
                clearButtonBusy(triggerButton);
            }
        }

        async function saveWorkspaceFileEdit() {
            const path = workspaceFileView.dataset.path || workspaceRelativePath;
            setButtonBusy(workspaceViewSave, 'Saving file...');
            setLoadingStatus(workspaceViewStatus, 'Saving file...');
            try {
                const response = await fetch('/api/workspace/operation', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ action: 'write', path, content: workspaceViewEditContent.value })
                });
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || 'Unable to save file.');
                }
                await viewWorkspaceFile({ path, name: path.split('/').pop() }, false);
                workspaceViewStatus.textContent = 'Saved.';
            } catch (requestError) {
                workspaceViewStatus.textContent = requestError.message || 'Unable to save file.';
            } finally {
                clearButtonBusy(workspaceViewSave);
            }
        }

        workspaceViewEdit?.addEventListener('click', () => {
            const path = workspaceFileView.dataset.path || workspaceRelativePath;
            viewWorkspaceFile({ path, name: path.split('/').pop() }, true, workspaceViewEdit);
        });
        workspaceViewSave?.addEventListener('click', saveWorkspaceFileEdit);
        workspaceViewCancel?.addEventListener('click', () => {
            const path = workspaceFileView.dataset.path || workspaceRelativePath;
            viewWorkspaceFile({ path, name: path.split('/').pop() }, false, workspaceViewCancel);
        });

        workspaceViewBack?.addEventListener('click', () => {
            const parts = workspaceRelativePath.split('/').filter(Boolean);
            parts.pop();
            workspaceRelativePath = parts.join('/');
            workspaceViewStart = null;
            workspaceViewEnd = null;
            workspaceMarkdownAnchorStart = null;
            workspaceMarkdownAnchorEnd = null;
            workspaceViewContent?.querySelectorAll('.workspace-view-line.selected, .workspace-markdown-block.selected').forEach((line) => line.classList.remove('selected'));
            if (workspaceFileViewHelp) {
                workspaceFileViewHelp.textContent = 'Mark lines below to add to a session.';
            }
            if (workspaceFileView) {
                workspaceFileView.hidden = true;
                workspaceFileView.dataset.binary = '0';
            }
            if (workspaceAddFiles) workspaceAddFiles.textContent = 'Add selected';
            if (workspaceFileViewHelp) {
                workspaceFileViewHelp.hidden = true;
                workspaceFileViewHelp.textContent = 'Mark lines below to add to a session.';
            }
            if (workspaceFilesPanel) {
                workspaceFilesPanel.hidden = false;
                workspaceFilesPanel.classList.remove('workspace-file-page-mode', 'workspace-edit-page-mode');
            }
            if (workspaceFileList) {
                workspaceFileList.hidden = false;
            }
            loadWorkspaceFiles();
        });

        function addSelectedWorkspaceLines() {
            if (workspaceViewStart === null || workspaceViewEnd === null || workspaceTargetSession === '') {
                workspaceViewStatus.textContent = 'Select a session and a whole-line range first.';
                return;
            }
            const first = Math.min(workspaceViewStart, workspaceViewEnd);
            const last = Math.max(workspaceViewStart, workspaceViewEnd);
            addWorkspaceFilesToSession([`${workspaceRelativePath}:${first}-${last}`], workspaceTargetSession);
        }

        function workspaceLocation(path, sessionName = null) {
            const suffix = path === ''
                ? ''
                : '/' + path.split('/').filter(Boolean).map((part) => encodeURIComponent(part)).join('/');
            if (sessionName || sessionWorkspaceActive) {
                const targetSession = sessionName || urlSessionName;
                return maiaUrl(`/session/${encodeURIComponent(targetSession)}${suffix}${path === '' ? '?workspace=1' : ''}`);
            }
            return maiaUrl(`/workspace/${encodeURIComponent(urlWorkspaceName)}${suffix}`);
        }

        function renderWorkspacePath(path) {
            renderWorkspaceBreadcrumb(workspaceFilePath, path, (event, target) => {
                if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) {
                    return;
                }
                event.preventDefault();
                workspaceRelativePath = target;
                loadWorkspaceFiles();
            });
        }

        function updateWorkspaceBrowserChrome() {
            const pureBrowser = workspaceRelativePath !== '';
            [settingsToggle, filesToggle, skillsToggle, toolsToggle].forEach((button) => {
                if (button) {
                    button.hidden = pureBrowser;
                }
            });
            if (composerActions && !sessionWorkspacePage) {
                composerActions.hidden = pureBrowser;
            }
        }

        async function loadWorkspaceFiles(updateUrl = true, triggerButton = null) {
            if (!workspaceFileList || !workspaceFilePath) {
                return;
            }
            updateWorkspaceBrowserChrome();
            if (updateUrl && (urlWorkspaceName || sessionWorkspaceActive)) {
                history.pushState({}, '', workspaceLocation(workspaceRelativePath));
            }
            workspaceFileStatus.classList.remove('error');
            const busyButtons = [...new Set([workspaceFileRefresh, triggerButton].filter(Boolean))];
            busyButtons.forEach((button) => setButtonBusy(button, 'Loading workspace files...'));
            setLoadingStatus(workspaceFileStatus, 'Loading workspace files...');
            try {
                const response = await fetch(`/api/workspace/files?path=${encodeURIComponent(workspaceRelativePath)}`);
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || 'Unable to list workspace files.');
                }
                workspaceEntries = Array.isArray(result.entries) ? result.entries : [];
                renderWorkspacePath(workspaceRelativePath);
                renderWorkspaceEntries();
                workspaceFileStatus.textContent = '';
                workspaceFileStatus.classList.remove('error');
            } catch (requestError) {
                workspaceFileStatus.textContent = requestError.message || 'Unable to list workspace files.';
                workspaceFileList.replaceChildren();
            } finally {
                busyButtons.forEach(clearButtonBusy);
                if (workspaceFileUp) {
                    workspaceFileUp.disabled = workspaceRelativePath === '';
                }
            }
        }

        workspaceSessionInput?.addEventListener('input', () => {
            workspaceTargetSession = '';
            updateWorkspaceSelectionActions();
            renderWorkspaceSessionMenu();
        });
        workspaceSessionInput?.addEventListener('focus', renderWorkspaceSessionMenu);
        workspaceSessionInput?.addEventListener('click', renderWorkspaceSessionMenu);
        workspaceSessionInput?.addEventListener('blur', () => {
            window.setTimeout(() => {
                if (workspaceSessionMenu) {
                    workspaceSessionMenu.hidden = true;
                }
            }, 100);
        });
        workspaceFileUp?.addEventListener('click', () => {
            const parts = workspaceRelativePath.split('/').filter(Boolean);
            parts.pop();
            workspaceRelativePath = parts.join('/');
            loadWorkspaceFiles(true, workspaceFileUp);
        });
        workspaceFileRefresh?.addEventListener('click', () => loadWorkspaceFiles(false, workspaceFileRefresh));
        function showWorkspaceFileError(requestError) {
            workspaceFileStatus.classList.add('error');
            workspaceFileStatus.textContent = requestError.message || 'Workspace operation failed.';
            workspaceFileStatus.hidden = false;
        }

        workspaceFileNewDirectory?.addEventListener('click', async () => {
            const name = window.prompt('Directory name:');
            if (!name) return;
            try { await workspaceOperation('mkdir', { path: workspaceRelativePath, name }, workspaceFileNewDirectory); }
            catch (requestError) { showWorkspaceFileError(requestError); }
        });
        workspaceFileNewFile?.addEventListener('click', async () => {
            const name = window.prompt('File name:');
            if (!name) return;
            try { await workspaceOperation('create', { path: workspaceRelativePath ? `${workspaceRelativePath}/${name}` : name }, workspaceFileNewFile); }
            catch (requestError) { showWorkspaceFileError(requestError); }
        });
        workspaceFileUpload?.addEventListener('click', () => workspaceFileUploadInput?.click());
        async function uploadWorkspaceFiles(files, triggerButton = null) {
            const fileList = Array.from(files || []);
            if (fileList.length === 0) {
                return;
            }
            const busyButton = triggerButton || workspaceFileUpload;
            setButtonBusy(busyButton, 'Uploading files...');
            setLoadingStatus(workspaceFileStatus, `Uploading ${fileList.length} file${fileList.length === 1 ? '' : 's'}...`);
            try {
                for (const file of fileList) {
                    const formData = new FormData();
                    formData.append('file', file);
                    formData.append('path', workspaceRelativePath);
                    const response = await fetch('/api/workspace/upload', { method: 'POST', body: formData });
                    const result = await response.json();
                    if (!response.ok || !result.ok) {
                        throw new Error(result.error || `Unable to upload ${file.name}.`);
                    }
                }
                await loadWorkspaceFiles(false);
                workspaceFileStatus.textContent = 'Upload complete.';
            } catch (requestError) {
                workspaceFileStatus.textContent = requestError.message || 'Unable to upload files.';
            } finally {
                clearButtonBusy(busyButton);
            }
        }

        workspaceFileUploadInput?.addEventListener('change', async () => {
            await uploadWorkspaceFiles(workspaceFileUploadInput.files, workspaceFileUpload);
            workspaceFileUploadInput.value = '';
        });

        function isMaiaRemoteDrag(event) {
            const types = event.dataTransfer?.types || [];
            return types.includes('application/x-maia-workspace-files') ||
                types.includes('application/x-maia-workspace-file');
        }

        workspaceFilesPanel?.addEventListener('dragover', (event) => {
            // Always cancel the browser's default navigation behavior. This
            // is important for drops carrying text/uri-list data.
            event.preventDefault();
            if (isMaiaRemoteDrag(event)) {
                event.dataTransfer.dropEffect = 'none';
                workspaceFilesPanel.classList.remove('workspace-drop-target');
                return;
            }
            if (event.dataTransfer?.types.includes('Files')) {
                event.dataTransfer.dropEffect = 'copy';
                workspaceFilesPanel.classList.add('workspace-drop-target');
            }
        });
        workspaceFilesPanel?.addEventListener('dragleave', (event) => {
            if (!workspaceFilesPanel.contains(event.relatedTarget)) {
                workspaceFilesPanel.classList.remove('workspace-drop-target');
            }
        });
        workspaceFilesPanel?.addEventListener('drop', async (event) => {
            event.preventDefault();
            event.stopPropagation();
            workspaceFilesPanel.classList.remove('workspace-drop-target');
            if (isMaiaRemoteDrag(event)) {
                return;
            }
            if (event.dataTransfer?.files?.length > 0) {
                await uploadWorkspaceFiles(event.dataTransfer.files);
            }
        });
        window.addEventListener('popstate', () => {
            if (!urlWorkspaceName) {
                return;
            }
            const currentPagePath = location.pathname.startsWith(maiaBasePath)
                ? location.pathname.slice(maiaBasePath.length) || '/'
                : location.pathname;
            const prefix = sessionWorkspacePage
                ? `/session/${encodeURIComponent(urlSessionName)}`
                : `/workspace/${encodeURIComponent(urlWorkspaceName)}`;
            const currentPath = currentPagePath.startsWith(prefix)
                ? currentPagePath.slice(prefix.length).replace(/^\//, '')
                : '';
            workspaceRelativePath = decodeURIComponent(currentPath);
            loadWorkspaceFiles(false);
        });
        async function addWorkspaceFilesToSession(paths, targetSession, triggerButton = null) {
            if (targetSession === '' || paths.length === 0) {
                return;
            }
            if (triggerButton) setButtonBusy(triggerButton, `Adding files to ${targetSession}...`);
            setLoadingStatus(workspaceFileStatus, `Adding files to ${targetSession}...`);
            try {
                for (const path of paths) {
                    const response = await fetch('/api/file/add', {
                        method: 'POST',
                        headers: {
                            'Content-Type': 'text/plain; charset=utf-8',
                            'X-MAIA-Session': targetSession
                        },
                        body: path
                    });
                    const result = await response.json();
                    if (!response.ok || !result.ok) {
                        throw new Error(result.error || `Unable to add ${path}.`);
                    }
                }
                workspaceFileStatus.textContent = `Files added to ${targetSession}.`;
            } catch (requestError) {
                workspaceFileStatus.textContent = requestError.message || 'Unable to add files.';
            } finally {
                clearButtonBusy(triggerButton);
            }
        }

        workspaceToggle?.addEventListener('click', async (event) => {
            event.preventDefault();
            if (!workspaceFilesPanel) {
                return;
            }
            const expanded = workspaceFilesPanel.hidden;
            workspaceFilesPanel.hidden = !expanded;
            workspaceToggle.setAttribute('aria-expanded', String(expanded));
            workspaceToggle.textContent = expanded ? 'Workspace \u25BE' : 'Workspace \u25B8';
            if (!expanded) {
                return;
            }
            if (selectedSessionWorkspaceName === '' && !urlWorkspaceName) {
                workspaceFileStatus.textContent = 'This session has no workspace configured.';
                workspaceFileStatus.classList.add('error');
                return;
            }
            sessionWorkspaceActive = true;
            workspaceTargetSession = urlSessionName || '';
            renderWorkspacePath(workspaceRelativePath);
            workspaceFileUp.disabled = workspaceRelativePath === '';
            if (workspaceRelativePath === '') {
                renderWorkspaceEntries();
            } else {
                await loadWorkspaceFiles(false);
            }
        });

        workspaceAddFiles?.addEventListener('click', async () => {
            if (workspaceTargetSession === '') {
                return;
            }
            updateWorkspaceSelectionActions();
            if (workspaceFileView?.dataset.binary === '1') {
                const path = workspaceFileView.dataset.path || workspaceRelativePath;
                await addWorkspaceFilesToSession([path], workspaceTargetSession, workspaceAddFiles);
                return;
            }
            if (workspaceViewStart !== null && workspaceViewEnd !== null) {
                const first = Math.min(workspaceViewStart, workspaceViewEnd);
                const last = Math.max(workspaceViewStart, workspaceViewEnd);
                await addWorkspaceFilesToSession([`${workspaceRelativePath}:${first}-${last}`], workspaceTargetSession, workspaceAddFiles);
                workspaceViewStart = null;
                workspaceViewEnd = null;
                workspaceMarkdownAnchorStart = null;
                workspaceMarkdownAnchorEnd = null;
                workspaceViewContent?.querySelectorAll('.workspace-view-line.selected, .workspace-markdown-block.selected').forEach((line) => line.classList.remove('selected'));
                if (workspaceFileViewHelp) {
                    workspaceFileViewHelp.textContent = 'Mark lines below to add to a session.';
                }
                updateWorkspaceSelectionActions();
                return;
            }
            if (workspaceSelectedFiles.size === 0) {
                return;
            }
            const paths = [...workspaceSelectedFiles];
            await addWorkspaceFilesToSession(paths, workspaceTargetSession, workspaceAddFiles);
            workspaceSelectedFiles.clear();
            renderWorkspaceEntries();
            updateWorkspaceSelectionActions();
        });

        workspaceFileCopySelected?.addEventListener('click', () => operateOnSelectedWorkspaceFiles('copy', workspaceFileCopySelected));
        workspaceFileMoveSelected?.addEventListener('click', () => operateOnSelectedWorkspaceFiles('move', workspaceFileMoveSelected));
        workspaceFileDeleteSelected?.addEventListener('click', () => operateOnSelectedWorkspaceFiles('delete', workspaceFileDeleteSelected));

        function showToolsLoading(message = 'Loading tools...') {
            toolsStatus.replaceChildren();
            const spinner = document.createElement('span');
            spinner.className = 'spinner';
            spinner.setAttribute('aria-hidden', 'true');
            const text = document.createElement('span');
            text.textContent = message;
            toolsStatus.append(text, spinner);
        }

        async function loadTools() {
            showToolsLoading();
            try {
                const scope = currentContextScope();
                const response = await fetch(`/api/tool/context?scope=${encodeURIComponent(scope)}`);
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || 'Unable to load tools.');
                }

                const toolScope = result.scope || 'session';
                toolsScope.textContent = `Toolset scope '${toolScope}'`;
                toolPatternList.replaceChildren();
                const patterns = result.patterns || [];
                for (const pattern of patterns) {
                    const item = document.createElement('li');
                    const value = document.createElement('span');
                    value.className = 'known-file-path';
                    value.textContent = pattern;
                    const remove = document.createElement('button');
                    remove.type = 'button';
                    remove.className = 'file-remove';
                    remove.textContent = 'X';
                    remove.title = `Remove tool pattern ${pattern}`;
                    remove.setAttribute('aria-label', `Remove tool pattern ${pattern}`);
                    remove.addEventListener('click', () => removeToolPattern(pattern, remove));
                    item.append(value, remove);
                    toolPatternList.appendChild(item);
                }

                availableToolsList.replaceChildren();
                const toolHeading = document.createElement('li');
                toolHeading.className = 'available-resource-heading';
                toolHeading.innerHTML = '<span class="available-resource-name">Name - Description</span><span>Effect</span><span>Allowed</span>';
                availableToolsList.appendChild(toolHeading);
                const tools = result.tools || [];
                availableToolNames = [];
                for (const tool of tools) {
                    if (!tool.name) {
                        continue;
                    }
                    const effects = Array.isArray(tool.effects) ? tool.effects.filter(Boolean) : [];
                    if (effects.length === 0) {
                        availableToolNames.push(tool.name);
                    } else {
                        for (const effect of effects) {
                            availableToolNames.push(`${tool.name}:${effect}`);
                        }
                    }
                }
                availableToolNames = [...new Set(availableToolNames)];
                for (const tool of tools) {
                    const item = document.createElement('li');
                    item.className = 'available-resource-row';
                    const value = document.createElement('span');
                    value.className = 'known-file-path available-resource-name';
                    value.textContent = tool.description
                        ? `${tool.name} - ${tool.description}`
                        : tool.name;
                    value.title = value.textContent;
                    const effectNames = Array.isArray(tool.effects) ? tool.effects.filter(Boolean) : [];
                    const effects = document.createElement('span');
                    effects.className = 'available-resource-effects';
                    effects.textContent = effectNames.length > 0
                        ? effectNames.join(', ')
                        : '(none)';
                    const toolPatternValue = effectNames.length > 0
                        ? `${tool.name}:${effectNames.join('+')}`
                        : tool.name;
                    const toolAllowed = Boolean(tool.allowed) || patterns.includes(toolPatternValue) || patterns.includes(tool.name);
                    let state;
                    if (toolAllowed) {
                        state = document.createElement('span');
                        state.textContent = 'Yes';
                        state.className = 'settings-status available-resource-state allowed';
                    } else {
                        state = document.createElement('button');
                        state.type = 'button';
                        state.textContent = 'No';
                        state.className = 'settings-status available-resource-state';
                        state.title = `Allow ${tool.name}`;
                        state.addEventListener('click', () => {
                            runAvailablePatternAction(
                                state,
                                toolPatternValue,
                                toolPattern,
                                addToolPattern
                            );
                        });
                    }
                    item.append(value, effects, state);
                    availableToolsList.appendChild(item);
                }

                toolsStatus.textContent = patterns.length > 0
                    ? ''
                    : 'No tool patterns configured.';
                if (tools.length === 0) {
                    const item = document.createElement('li');
                    item.textContent = 'No available tools.';
                    availableToolsList.appendChild(item);
                }
                toolsLoaded = true;
            } catch (requestError) {
                toolsStatus.textContent = requestError.message || 'Unable to load tools.';
                toolsLoaded = false;
            }
        }

        function commonResourceCompletionPrefix(values) {
            if (values.length === 0) {
                return '';
            }
            let prefix = values[0];
            for (const value of values.slice(1)) {
                let length = 0;
                while (length < prefix.length && length < value.length &&
                       prefix[length] === value[length]) {
                    length++;
                }
                prefix = prefix.slice(0, length);
            }
            return prefix;
        }

        function setupResourceCompletion(input, menu, getNames) {
            let candidates = [];
            let query = '';
            const render = () => {
                menu.replaceChildren();
                if (candidates.length === 0) {
                    menu.hidden = true;
                    return;
                }
                for (const candidate of candidates) {
                    const option = document.createElement('button');
                    option.type = 'button';
                    option.className = 'resource-completion-option';
                    option.textContent = candidate;
                    option.addEventListener('mousedown', (event) => {
                        event.preventDefault();
                        input.value = candidate;
                        menu.hidden = true;
                        input.focus();
                    });
                    menu.appendChild(option);
                }
                menu.hidden = false;
            };
            const refresh = () => {
                query = input.value;
                const names = getNames();
                candidates = query.includes('*') || query.includes('?')
                    ? []
                    : names.filter((name) => name.startsWith(query));
                render();
            };
            const complete = () => {
                if (candidates.length === 0 || query !== input.value) {
                    return;
                }
                const completion = candidates.length === 1
                    ? candidates[0]
                    : commonResourceCompletionPrefix(candidates);
                if (completion !== '' && completion !== input.value) {
                    input.value = completion;
                    refresh();
                }
                input.focus();
            };
            input.addEventListener('input', refresh);
            input.addEventListener('keydown', (event) => {
                if (event.key === 'Tab' && (input.value === '' ||
                    (candidates.length > 0 && query === input.value))) {
                    event.preventDefault();
                    if (candidates.length > 0 && query === input.value) {
                        complete();
                    } else {
                        refresh();
                    }
                } else if (event.key === 'Escape') {
                    menu.hidden = true;
                }
            });
            input.addEventListener('blur', () => {
                window.setTimeout(() => {
                    menu.hidden = true;
                }, 100);
            });
            return { refresh };
        }

        const toolCompletion = setupResourceCompletion(
            toolPattern,
            document.getElementById('tool-completion-menu'),
            () => availableToolNames
        );
        const skillCompletion = setupResourceCompletion(
            skillPattern,
            document.getElementById('skill-completion-menu'),
            () => availableSkillNames
        );

        async function runAvailablePatternAction(button, pattern, input, action) {
            const originalText = button.textContent;
            button.classList.add('busy');
            button.disabled = true;
            button.replaceChildren();
            const spinner = document.createElement('span');
            spinner.className = 'spinner';
            spinner.setAttribute('aria-hidden', 'true');
            button.appendChild(spinner);
            input.value = pattern;
            try {
                await action();
            } finally {
                if (button.isConnected) {
                    button.replaceChildren(document.createTextNode(originalText));
                    button.classList.remove('busy');
                    button.disabled = false;
                }
            }
        }

        async function addToolPattern() {
            const pattern = toolPattern.value.trim();
            if (pattern === '') {
                toolsStatus.textContent = 'Enter a tool pattern.';
                toolPattern.focus();
                return;
            }
            setButtonBusy(toolPatternAdd, 'Adding tool pattern...');
            toolPattern.disabled = true;
            setLoadingStatus(toolsStatus, 'Adding tool pattern...');
            try {
                const scope = currentContextScope();
                const response = await fetch(`/api/tool/append?scope=${encodeURIComponent(scope)}`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'text/plain; charset=utf-8' },
                    body: pattern
                });
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || 'Unable to add tool pattern.');
                }
                toolPattern.value = '';
                toolsLoaded = false;
                await loadTools();
            } catch (requestError) {
                toolsStatus.textContent = requestError.message || 'Unable to add tool pattern.';
            } finally {
                clearButtonBusy(toolPatternAdd);
                toolPattern.disabled = false;
                toolPattern.focus();
            }
        }

        async function removeToolPattern(pattern, button) {
            setButtonBusy(button, `Removing ${pattern}...`);
            setLoadingStatus(toolsStatus, `Removing ${pattern}...`);
            try {
                const scope = currentContextScope();
                const response = await fetch(`/api/tool/disable?scope=${encodeURIComponent(scope)}`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'text/plain; charset=utf-8' },
                    body: pattern
                });
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || 'Unable to remove tool pattern.');
                }
                toolsLoaded = false;
                await loadTools();
            } catch (requestError) {
                toolsStatus.textContent = requestError.message || 'Unable to remove tool pattern.';
            } finally {
                clearButtonBusy(button);
            }
        }

        async function updateToolDefinitions(action, button) {
            if (!window.confirm(action === 'clear'
                ? 'Clear the session tool definitions? This leaves no tools allowed at this scope.'
                : 'Delete the session tool definitions? The effective definition will be inherited from another scope.')) {
                return;
            }
            const otherButton = button === toolClear ? toolDelete : toolClear;
            otherButton.disabled = true;
            setButtonBusy(button, action === 'clear' ? 'Clearing tool definitions...' : 'Deleting tool definitions...');
            setLoadingStatus(toolsStatus, action === 'clear' ? 'Clearing tool definitions...' : 'Deleting tool definitions...');
            try {
                const scope = currentContextScope();
                const response = await fetch(`/api/tool/${action}?scope=${encodeURIComponent(scope)}`, { method: 'POST' });
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || `Unable to ${action} tool definitions.`);
                }
                toolsLoaded = false;
                await loadTools();
            } catch (requestError) {
                toolsStatus.textContent = requestError.message || `Unable to ${action} tool definitions.`;
            } finally {
                clearButtonBusy(button);
                otherButton.disabled = false;
            }
        }

        toolClear.addEventListener('click', () => updateToolDefinitions('clear', toolClear));
        toolDelete.addEventListener('click', () => updateToolDefinitions('delete', toolDelete));

        async function refreshTools() {
            toolsRefresh.disabled = true;
            showToolsLoading('Refreshing tools...');
            try {
                const scope = currentContextScope();
                const response = await fetch('/api/tool/context', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ action: 'refresh', scope })
                });
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || 'Unable to refresh tools.');
                }
                toolsLoaded = false;
                await loadTools();
            } catch (requestError) {
                toolsStatus.textContent = requestError.message || 'Unable to refresh tools.';
            } finally {
                toolsRefresh.disabled = false;
            }
        }

        toolsRefresh.addEventListener('click', refreshTools);

        toolsToggle.addEventListener('click', async () => {
            const expanded = toolsPanel.hidden;
            toolsPanel.hidden = !expanded;
            toolsToggle.setAttribute('aria-expanded', String(expanded));
            toolsToggle.textContent = expanded ? 'Tools \u25BE' : 'Tools \u25B8';
            if (expanded && !toolsLoaded) {
                await loadTools();
            }
        });

        toolPatternAdd.addEventListener('click', addToolPattern);
        toolPattern.addEventListener('keydown', (event) => {
            if (event.key === 'Enter') {
                event.preventDefault();
                addToolPattern();
            }
        });

        function currentContextScope() {
            // Profiles are resources, not CLI definition scopes. Their page
            // uses the home-level tool and skill context.
            return urlProfileName ? 'home'
                : (urlWorkspaceName ? 'workspace'
                    : (urlHomeName ? 'home' : 'session'));
        }

        function showSkillsLoading(message = 'Loading skills...') {
            skillsStatus.replaceChildren();
            const spinner = document.createElement('span');
            spinner.className = 'spinner';
            spinner.setAttribute('aria-hidden', 'true');
            const text = document.createElement('span');
            text.textContent = message;
            skillsStatus.append(spinner, text);
        }

        async function loadSkills() {
            showSkillsLoading();
            try {
                const scope = currentContextScope();
                const response = await fetch(`/api/skill/context?scope=${encodeURIComponent(scope)}`);
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || 'Unable to load skills.');
                }

                skillsScope.textContent = `Skill scope '${result.scope || scope}'`;
                skillPatternList.replaceChildren();
                for (const pattern of result.patterns || []) {
                    const item = document.createElement('li');
                    const value = document.createElement('span');
                    value.className = 'known-file-path';
                    value.textContent = pattern;
                    const remove = document.createElement('button');
                    remove.type = 'button';
                    remove.className = 'file-remove';
                    remove.textContent = 'X';
                    remove.title = `Remove skill pattern ${pattern}`;
                    remove.setAttribute('aria-label', `Remove skill pattern ${pattern}`);
                    remove.addEventListener('click', () => updateSkillContext('disable', pattern, remove));
                    item.append(value, remove);
                    skillPatternList.appendChild(item);
                }

                availableSkillsList.replaceChildren();
                const skillHeading = document.createElement('li');
                skillHeading.className = 'available-resource-heading';
                skillHeading.innerHTML = '<span class="available-resource-name">Name - Description</span><span>Allowed</span><span>In memory</span>';
                availableSkillsList.appendChild(skillHeading);
                const skills = result.skills || [];
                availableSkillNames = skills.map((skill) => skill.name).filter(Boolean);
                for (const skill of skills) {
                    const item = document.createElement('li');
                    item.className = 'available-resource-row';
                    const value = document.createElement('span');
                    value.className = 'known-file-path available-resource-name';
                    value.textContent = skill.description
                        ? `${skill.name} - ${skill.description}`
                        : skill.name;
                    value.title = value.textContent;
                    let state;
                    if (skill.allowed) {
                        state = document.createElement('span');
                        state.textContent = 'Yes';
                        state.className = 'settings-status available-resource-state allowed';
                    } else {
                        state = document.createElement('button');
                        state.type = 'button';
                        state.textContent = 'No';
                        state.className = 'settings-status available-resource-state';
                        state.title = `Allow ${skill.name}`;
                        state.addEventListener('click', () => {
                            runAvailablePatternAction(
                                state,
                                skill.name,
                                skillPattern,
                                addSkillPattern
                            );
                        });
                    }
                    const memoryButton = document.createElement('button');
                    memoryButton.type = 'button';
                    memoryButton.className = 'settings-status available-resource-state skill-memory-state';
                    memoryButton.disabled = !skill.allowed;
                    memoryButton.textContent = skill.memory ? 'Yes' : 'No';
                    memoryButton.title = skill.memory
                        ? `Remove ${skill.name} from memory`
                        : `Load ${skill.name} into memory`;
                    memoryButton.addEventListener('click', () => {
                        updateSkillMemory(skill.name, memoryButton, !skill.memory);
                    });
                    item.append(value, state, memoryButton);
                    availableSkillsList.appendChild(item);
                }
                if ((result.skills || []).length === 0) {
                    const item = document.createElement('li');
                    item.textContent = 'No available skills.';
                    availableSkillsList.appendChild(item);
                }
                skillsStatus.textContent = (result.patterns || []).length > 0
                    ? ''
                    : 'No skill patterns configured.';
            } catch (requestError) {
                skillsStatus.textContent = requestError.message || 'Unable to load skills.';
            }
        }

        async function updateSkillMemory(name, button, desired) {
            const originalText = button.textContent;
            button.classList.add('busy');
            button.disabled = true;
            button.replaceChildren();
            const spinner = document.createElement('span');
            spinner.className = 'spinner';
            spinner.setAttribute('aria-hidden', 'true');
            button.appendChild(spinner);
            skillsStatus.textContent = desired
                ? `Remembering ${name}...`
                : `Forgetting ${name}...`;
            try {
                const response = await fetch(`/api/skill/context?scope=${encodeURIComponent(currentContextScope())}`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ action: 'memory', name, remember: desired })
                });
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || 'Unable to update skill memory.');
                }
                button.textContent = desired ? 'Yes' : 'No';
                button.title = desired
                    ? `Remove ${name} from memory`
                    : `Load ${name} into memory`;
                skillsStatus.textContent = desired ? `${name} is in memory.` : `${name} removed from memory.`;
            } catch (requestError) {
                button.textContent = originalText;
                skillsStatus.textContent = requestError.message || 'Unable to update skill memory.';
            } finally {
                button.classList.remove('busy');
                button.disabled = false;
            }
        }

        async function addSkillPattern() {
            const pattern = skillPattern.value.trim();
            if (pattern === '') {
                skillsStatus.textContent = 'Enter a skill pattern.';
                skillPattern.focus();
                return;
            }
            setButtonBusy(skillPatternAdd, 'Adding skill pattern...');
            skillPattern.disabled = true;
            setLoadingStatus(skillsStatus, 'Adding skill pattern...');
            try {
                const response = await fetch(`/api/skill/context?scope=${encodeURIComponent(currentContextScope())}`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ action: 'append', pattern })
                });
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || 'Unable to add skill pattern.');
                }
                skillPattern.value = '';
                await loadSkills();
            } catch (requestError) {
                skillsStatus.textContent = requestError.message || 'Unable to add skill pattern.';
            } finally {
                clearButtonBusy(skillPatternAdd);
                skillPattern.disabled = false;
                skillPattern.focus();
            }
        }

        async function updateSkillContext(action, patternOrButton, maybeButton) {
            const pattern = typeof patternOrButton === 'string' ? patternOrButton : '';
            const button = maybeButton || patternOrButton;
            if (action !== 'disable' && !window.confirm(action === 'clear'
                ? 'Clear the skill definitions at this scope?'
                : 'Delete the skill definitions at this scope?')) {
                return;
            }
            const otherButton = action === 'clear' ? skillDelete
                : (action === 'delete' ? skillClear : null);
            if (otherButton) otherButton.disabled = true;
            const message = `${action === 'disable' ? 'Removing' : action === 'clear' ? 'Clearing' : 'Deleting'} skill definitions...`;
            setButtonBusy(button, `${message}`);
            setLoadingStatus(skillsStatus, message);
            try {
                const response = await fetch(`/api/skill/context?scope=${encodeURIComponent(currentContextScope())}`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ action, ...(pattern !== '' ? { pattern } : {}) })
                });
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || `Unable to ${action} skill definitions.`);
                }
                await loadSkills();
            } catch (requestError) {
                skillsStatus.textContent = requestError.message || `Unable to ${action} skill definitions.`;
            } finally {
                clearButtonBusy(button);
                if (otherButton) otherButton.disabled = false;
            }
        }

        async function refreshSkills() {
            skillsRefresh.disabled = true;
            showSkillsLoading('Refreshing skills...');
            try {
                const scope = currentContextScope();
                const response = await fetch('/api/skill/context', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ action: 'refresh', scope })
                });
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || 'Unable to refresh skills.');
                }
                await loadSkills();
            } catch (requestError) {
                skillsStatus.textContent = requestError.message || 'Unable to refresh skills.';
            } finally {
                skillsRefresh.disabled = false;
            }
        }

        skillsRefresh.addEventListener('click', refreshSkills);

        skillsToggle.addEventListener('click', async () => {
            const expanded = skillsPanel.hidden;
            skillsPanel.hidden = !expanded;
            skillsToggle.setAttribute('aria-expanded', String(expanded));
            skillsToggle.textContent = expanded ? 'Skills \u25BE' : 'Skills \u25B8';
            if (expanded) {
                await loadSkills();
            }
        });
        skillPatternAdd.addEventListener('click', addSkillPattern);
        skillPattern.addEventListener('keydown', (event) => {
            if (event.key === 'Enter') {
                event.preventDefault();
                addSkillPattern();
            }
        });
        skillClear.addEventListener('click', () => updateSkillContext('clear', skillClear));
        skillDelete.addEventListener('click', () => updateSkillContext('delete', skillDelete));

        let firstIndex = null;
        let lastIndex = null;
        let historyItems = [];
        let loadingEarlier = false;

        function formatToolArguments(argumentsValue) {
            if (typeof argumentsValue !== 'string') {
                return JSON.stringify(argumentsValue ?? {}, null, 2);
            }

            try {
                return JSON.stringify(JSON.parse(argumentsValue), null, 2);
            } catch (_) {
                return argumentsValue;
            }
        }

        function formatJson(value) {
            return JSON.stringify(value, null, 2);
        }

        function formatTimestamp(timestamp) {
            if (typeof timestamp !== 'string') {
                return '';
            }

            const match = timestamp.match(/^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})/);
            if (!match) {
                return timestamp;
            }
            return `${match[1]}-${match[2]}-${match[3]} ${match[4]}:${match[5]}:${match[6]}`;
        }

        const historyUrlPattern = /https?:\/\/[^\s<>"']+/gi;

        function appendHistoryPlainText(parent, text) {
            let offset = 0;
            historyUrlPattern.lastIndex = 0;
            for (const match of text.matchAll(historyUrlPattern)) {
                const rawUrl = match[0];
                let url = rawUrl;
                let trailing = '';
                while (/[.,!?;:)\\]}]$/.test(url)) {
                    trailing = url.slice(-1) + trailing;
                    url = url.slice(0, -1);
                }
                const start = match.index ?? offset;
                if (start > offset) {
                    parent.appendChild(document.createTextNode(text.slice(offset, start)));
                }
                if (url === '') {
                    parent.appendChild(document.createTextNode(rawUrl));
                } else {
                    const link = document.createElement('a');
                    link.href = url;
                    link.target = '_blank';
                    link.rel = 'noopener noreferrer';
                    link.textContent = url;
                    parent.appendChild(link);
                    if (trailing !== '') {
                        parent.appendChild(document.createTextNode(trailing));
                    }
                }
                offset = start + rawUrl.length;
            }
            if (offset < text.length) {
                parent.appendChild(document.createTextNode(text.slice(offset)));
            }
        }

        function appendHistoryText(parent, text, parts = null) {
            const sessionHistory = Boolean(urlSessionName || selectedSessionName);
            if (!Array.isArray(parts) || parts.length === 0) {
                if (sessionHistory) {
                    parent.replaceChildren();
                    appendHistoryPlainText(parent, text);
                } else {
                    parent.textContent = text;
                }
                return;
            }
            parent.replaceChildren();
            for (const part of parts) {
                const value = String(part?.text ?? '');
                if (typeof part?.path === 'string' && part.path !== '') {
                    const link = document.createElement('a');
                    link.href = workspaceLocation(part.path, typeof part.session === 'string' ? part.session : null);
                    link.textContent = value;
                    parent.appendChild(link);
                } else if (sessionHistory) {
                    appendHistoryPlainText(parent, value);
                } else {
                    parent.appendChild(document.createTextNode(value));
                }
            }
        }

        function createToolCallElement(name, argumentsText) {
            const element = document.createElement('div');
            element.className = 'tool-call';

            const details = document.createElement('details');
            const summary = document.createElement('summary');
            const summaryLabel = `Tool call: ${name}`;
            summary.textContent = summaryLabel;

            const argumentsElement = document.createElement('pre');
            argumentsElement.textContent = argumentsText;

            details.append(summary, argumentsElement);
            element.appendChild(details);
            return element;
        }

        function appendBackup(element, item) {
            if (!item.backup || typeof item.backup !== 'object') {
                return;
            }

            const backup = document.createElement('div');
            backup.className = 'message-backup';
            backup.hidden = true;

            const backupContent = document.createElement('div');
            backupContent.className = 'message-backup-content';

            if (Object.prototype.hasOwnProperty.call(item.backup, 'content') &&
                item.backup.content !== null && item.backup.content !== undefined) {
                const content = document.createElement('div');
                appendHistoryText(content, String(item.backup.content), item.backup.contentParts);
                backupContent.appendChild(content);
            }

            for (const toolCall of item.backup.tool_calls ?? []) {
                const functionCall = toolCall.function ?? {};
                const name = functionCall.name ?? 'unknown';
                const argumentsText = formatToolArguments(functionCall.arguments ?? {});
                backupContent.appendChild(createToolCallElement(name, argumentsText));
            }

            if (Object.prototype.hasOwnProperty.call(item.backup, 'data')) {
                const data = document.createElement('pre');
                data.textContent = formatJson(item.backup.data);
                backupContent.appendChild(data);
            }

            if (!backupContent.hasChildNodes()) {
                return;
            }

            backup.appendChild(backupContent);
            element.appendChild(backup);

            const footer = element.querySelector('.message-footer');
            const toggle = document.createElement('button');
            toggle.type = 'button';
            toggle.className = 'backup-toggle';
            toggle.textContent = 'Show original';
            toggle.addEventListener('click', () => {
                backup.hidden = !backup.hidden;
                toggle.textContent = backup.hidden ? 'Show original' : 'Hide original';
            });
            footer.appendChild(toggle);
        }

        function appendFooter(element, item) {
            const footer = document.createElement('div');
            footer.className = 'message-footer';

            if (item.timestamp) {
                const timestamp = document.createElement('span');
                timestamp.className = 'message-time';
                timestamp.textContent = formatTimestamp(item.timestamp);
                timestamp.title = item.timestamp;
                footer.appendChild(timestamp);
            }

            element.appendChild(footer);
            appendBackup(element, item);

            if (!footer.hasChildNodes()) {
                footer.remove();
            } else {
                // Keep the controls below the current content and any expanded original.
                element.appendChild(footer);
            }
        }

        function appendMessage(type, text, scroll = true, item = {}) {
            const element = document.createElement('div');
            element.className = `message ${type}`;
            const content = document.createElement('div');
            appendHistoryText(content, text, item.contentParts);
            element.appendChild(content);
            appendFooter(element, item);
            conversation.appendChild(element);
            if (scroll) {
                element.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
            }
            return element;
        }

        function appendToolCall(name, argumentsText, scroll = true, item = {}) {
            const element = document.createElement('div');
            element.className = 'message tool-call';
            element.appendChild(createToolCallElement(name, argumentsText));
            appendFooter(element, item);
            conversation.appendChild(element);

            if (scroll) {
                element.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
            }
            return element;
        }

        function isHiddenHistoryItem(item) {
            return item.hidden === true || item.hidden === 1 || item.hidden === 'true';
        }

        async function refreshHistoryAfterMutation() {
            const result = await fetchHistory('all');
            historyItems = result.items;
            firstIndex = result.firstIndex;
            lastIndex = result.lastIndex;
            renderHistory(historyItems);
            updateEarlierButton();
        }

        async function performHistoryAction(action, item, content = null) {
            const body = {
                action,
                index: Number(item.index)
            };
            if (action === 'prune' || action === 'cut') {
                body.role = item.role;
                body.roleIndex = Number(item[`${item.role}_index`]);
            }
            if (action === 'replace') {
                body.content = content ?? '';
            }
            const response = await fetch('/api/history/action', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(body)
            });
            const result = await response.json();
            if (!response.ok || !result.ok) {
                throw new Error(result.error || 'Unable to update history.');
            }
            await refreshHistoryAfterMutation();
        }

        function appendHistoryActions(element, item) {
            if (!element || element.querySelector('.history-entry-actions')) {
                return;
            }
            element.classList.add('history-entry');
            const actions = document.createElement('div');
            actions.className = 'history-entry-actions';
            const definitions = [
                ['edit', '✎', 'Edit this entry'],
                [isHiddenHistoryItem(item) ? 'unhide' : 'hide', isHiddenHistoryItem(item) ? '⊙' : '⊘', isHiddenHistoryItem(item) ? 'Unhide this entry' : 'Hide this entry'],
                ['prune', '⊖', 'Prune this entry'],
                ['cut', '⌧', 'Clear this entry'],
                ['delete', '×', 'Delete this entry'],
                ['delete-below', '×↓', 'Delete this entry and all below']
            ];
            for (const [action, icon, label] of definitions) {
                if (action === 'prune' && !['assistant', 'tool'].includes(item.role)) {
                    continue;
                }
                const actionIcon = action === 'prune' ? '\u224B' : icon;
                const actionLabel = action === 'prune' ? 'Reduce' : label;
                const button = document.createElement('button');
                button.type = 'button';
                button.className = 'history-entry-action';
                button.textContent = actionIcon;
                button.title = actionLabel;
                button.setAttribute('aria-label', actionLabel);
                if (item.role === 'tool') {
                    const matchingCalls = historyItems.flatMap((candidate) =>
                        candidate.role === 'assistant' && Array.isArray(candidate.tool_calls)
                            ? candidate.tool_calls.filter((toolCall) => toolCall?.id === item.tool_call_id)
                                .map(() => candidate)
                            : []
                    );
                    const hasMatchingCall = matchingCalls.length > 0;
                    const hasVisibleMatchingCall = matchingCalls.some((candidate) => !isHiddenHistoryItem(candidate));
                    if (hasMatchingCall && ['hide', 'delete', 'delete-below'].includes(action)) {
                        button.disabled = true;
                        button.title = 'Tool results cannot be hidden or deleted directly; act on the assistant tool call instead.';
                        button.setAttribute('aria-label', button.title);
                    } else if (action === 'unhide' && !hasVisibleMatchingCall) {
                        button.disabled = true;
                        button.title = hasMatchingCall
                            ? 'Unhide the assistant tool call first.'
                            : 'This tool result has no matching assistant tool call.';
                        button.setAttribute('aria-label', button.title);
                    }
                } else if (item.role === 'assistant' && action === 'unhide' && Array.isArray(item.tool_calls)) {
                    const allResultsExist = item.tool_calls.every((toolCall) =>
                        historyItems.some((candidate) =>
                            candidate.role === 'tool' && candidate.tool_call_id === toolCall?.id
                        )
                    );
                    if (!allResultsExist) {
                        button.disabled = true;
                        button.title = 'This assistant response has a tool call with no matching tool result.';
                        button.setAttribute('aria-label', button.title);
                    }
                }
                button.addEventListener('click', async (event) => {
                    event.stopPropagation();
                    if (action === 'edit') {
                        historyEditDialog.dataset.index = String(item.index);
                        historyEditContent.value = String(item.content ?? '');
                        historyEditError.hidden = true;
                        historyEditDialog.showModal();
                        historyEditContent.focus();
                        return;
                    }
                    const confirmation = action === 'delete-below'
                        ? 'Delete this history entry and all entries below it? This cannot be undone.'
                        : action === 'delete'
                            ? 'Delete this history entry? This cannot be undone.'
                            : action === 'cut'
                                ? 'Clear/cut this history entry? Its original content will be retained as a backup.'
                                : action === 'prune'
                                    ? 'Reduce this history entry? Its original content will be retained as a backup.'
                                    : '';
                    if (confirmation && !window.confirm(confirmation)) {
                        return;
                    }
                    setButtonBusy(button, `${actionLabel}...`);
                    try {
                        await performHistoryAction(action, item);
                    } catch (requestError) {
                        showError(requestError.message || 'Unable to update history.');
                    } finally {
                        clearButtonBusy(button);
                    }
                });
                actions.appendChild(button);
            }
            element.appendChild(actions);
            element.addEventListener('click', () => {
                conversation.querySelectorAll('.history-entry-selected').forEach((entry) => {
                    entry.classList.remove('history-entry-selected');
                });
                element.classList.add('history-entry-selected');
            });
        }

        function renderHistoryItem(item) {
            const elementBefore = conversation.lastElementChild;

            switch (item.role) {
                case 'user':
                    appendMessage('user', String(item.content ?? ''), false, item);
                    break;

                case 'assistant': {
                    const element = document.createElement('div');
                    element.className = 'message server';

                    if (item.content !== null && item.content !== undefined && item.content !== '') {
                        const content = document.createElement('div');
                        appendHistoryText(content, String(item.content), item.contentParts);
                        element.appendChild(content);
                    }

                    for (const toolCall of item.tool_calls ?? []) {
                        const functionCall = toolCall.function ?? {};
                        const name = functionCall.name ?? 'unknown';
                        const argumentsText = formatToolArguments(functionCall.arguments ?? {});
                        element.appendChild(createToolCallElement(name, argumentsText));
                    }

                    appendFooter(element, item);
                    conversation.appendChild(element);
                    break;
                }

                case 'tool':
                    appendMessage('tool', String(item.content ?? ''), false, item);
                    break;

                case 'reasoning':
                    // Reasoning is intentionally kept in historyItems but not
                    // rendered. Its content is usually empty and may contain
                    // provider-specific or encrypted data.
                    break;

                default:
                    if (item.content !== null && item.content !== undefined) {
                        appendMessage('server', String(item.content), false, item);
                    }
                    break;
            }

            // Mark the element produced for a hidden history item without
            // changing its normal role-specific background color.
            if (conversation.lastElementChild !== elementBefore && conversation.lastElementChild?.classList.contains('message')) {
                appendHistoryActions(conversation.lastElementChild, item);
                if (isHiddenHistoryItem(item)) {
                    conversation.lastElementChild.classList.add('hidden-entry');
                }
            }
        }

        function renderHiddenGroup(items) {
            const group = document.createElement('details');
            group.className = 'hidden-group';

            const summary = document.createElement('summary');
            const turns = new Set(
                items
                    .filter((item) => item.role === 'user')
                    .map((item) => item.user_index)
                    .filter((index) => index !== null && index !== undefined)
            );
            const turnCount = turns.size || items.filter((item) => item.role === 'user').length;
            const summaryLabel = `Show ${items.length} hidden ${items.length === 1 ? 'entry' : 'entries'} · ${turnCount} ${turnCount === 1 ? 'turn' : 'turns'} affected`;
            summary.textContent = summaryLabel;

            const contents = document.createElement('div');
            contents.className = 'hidden-group-items';
            group.append(summary, contents);
            conversation.appendChild(group);

            for (const item of items) {
                renderHistoryItem(item);
                const element = conversation.lastElementChild;
                if (element && element !== group) {
                    contents.appendChild(element);
                }
            }
        }

        function showHistoryLoading(message = 'Loading conversation...') {
            conversation.replaceChildren();
            const status = document.createElement('div');
            status.className = 'history-loading';
            const spinner = document.createElement('span');
            spinner.className = 'spinner';
            spinner.setAttribute('aria-hidden', 'true');
            const text = document.createElement('span');
            text.textContent = message;
            status.append(text, spinner);
            conversation.appendChild(status);
        }

        function updatePendingResponse(element, statusText, output = '') {
            element.replaceChildren();
            element.classList.add('pending-response');

            if (output !== '') {
                const content = document.createElement('div');
                content.textContent = output;
                element.appendChild(content);
            }

            const status = document.createElement('div');
            status.className = 'pending-status';
            const spinner = document.createElement('span');
            spinner.className = 'spinner';
            spinner.setAttribute('aria-hidden', 'true');
            const text = document.createElement('span');
            text.textContent = statusText;
            status.append(spinner, text);
            element.appendChild(status);
        }

        function appendPartialResponse(output, beforeElement = null) {
            if (output === '') {
                return;
            }
            const details = document.createElement('details');
            details.className = 'partial-response';
            const summary = document.createElement('summary');
            summary.textContent = 'Raw response';
            const content = document.createElement('div');
            content.className = 'partial-response-content';
            content.textContent = output;
            details.append(summary, content);
            conversation.insertBefore(details, beforeElement);
        }

        function conversationIsNearBottom() {
            return window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 200;
        }

        function renderHistory(items, scrollToEnd = true) {
            conversation.replaceChildren();
            let hiddenItems = [];
            for (const item of items) {
                if (isHiddenHistoryItem(item)) {
                    hiddenItems.push(item);
                    continue;
                }
                if (hiddenItems.length > 0) {
                    renderHiddenGroup(hiddenItems);
                    hiddenItems = [];
                }
                renderHistoryItem(item);
            }
            if (hiddenItems.length > 0) {
                renderHiddenGroup(hiddenItems);
            }

            const numericFirstIndex = Number(firstIndex);
            if (items.length === 0 || (Number.isInteger(numericFirstIndex) && numericFirstIndex <= 1)) {
                const sessionStart = document.createElement('div');
                sessionStart.className = 'session-start';
                sessionStart.textContent = 'Beginning of session';
                conversation.prepend(sessionStart);
            }

            if (scrollToEnd) {
                conversation.lastElementChild?.scrollIntoView({
                    behavior: 'auto',
                    block: 'nearest'
                });
            }
        }

        function updateEarlierButton() {
            const numericFirstIndex = Number(firstIndex);
            const earlierMessages = Number.isInteger(numericFirstIndex)
                ? Math.max(0, numericFirstIndex - 1)
                : 0;
            const userIndexes = historyItems
                .filter((item) => item.role === 'user')
                .map((item) => Number(item.user_index))
                .filter((index) => Number.isInteger(index));
            const earlierTurns = userIndexes.length > 0 ? Math.max(0, Math.min(...userIndexes)) : 0;
            const hasEarlier = userIndexes.length > 0
                ? Math.min(...userIndexes) > 0
                : Number.isInteger(numericFirstIndex) && numericFirstIndex > 1;

            loadEarlier.hidden = !hasEarlier;
            turnCountControl.hidden = !hasEarlier;
            historyRemaining.hidden = !hasEarlier;
            loadAllHistory.hidden = !hasEarlier;
            if (hasEarlier) {
                historyRemaining.textContent = `Earlier history: ${earlierMessages} messages · ${earlierTurns} turns`;
            }
        }

        function showError(text) {
            error.textContent = text;
            error.hidden = false;
        }

        let knownSessions = [];
        let displayedSessions = [];
        let selectedSessionName = urlSessionName;
        let selectionController = null;
        let selectionRequestId = 0;

        function updateSessionWorkspaceControls() {
            if (urlWorkspaceName || urlProfileName || urlHomeName || sessionWorkspacePage) {
                return;
            }
            const selectedSession = knownSessions.find((session) => session.name === selectedSessionName);
            selectedSessionWorkspaceName = String(selectedSession?.workspace ?? '').trim();
            const hasWorkspace = selectedSessionWorkspaceName !== '';
            if (!hasWorkspace) {
                if (filesPanel) filesPanel.hidden = true;
                if (workspaceFilesPanel) workspaceFilesPanel.hidden = true;
            }
            const filesExpanded = hasWorkspace && Boolean(filesPanel && !filesPanel.hidden);
            const workspaceExpanded = hasWorkspace && Boolean(workspaceFilesPanel && !workspaceFilesPanel.hidden);
            if (filesToggle) {
                filesToggle.hidden = !hasWorkspace;
                filesToggle.setAttribute('aria-expanded', String(filesExpanded));
                filesToggle.textContent = `Files ${String.fromCharCode(filesExpanded ? 0x25BE : 0x25B8)}`;
            }
            if (workspaceToggle) {
                workspaceToggle.hidden = !hasWorkspace;
                workspaceToggle.setAttribute('aria-expanded', String(workspaceExpanded));
                workspaceToggle.textContent = `Workspace ${String.fromCharCode(workspaceExpanded ? 0x25BE : 0x25B8)}`;
            }
        }

        function renderSessions(sessions, selected) {
            displayedSessions = sessions;
            sessionList.replaceChildren();
            sessionListPlaceholder.textContent = sessions.length > 0
                ? ''
                : 'No matching sessions.';
            sessionListPlaceholder.hidden = sessions.length > 0;

            selectedSessionName = selected || null;
            updateSessionWorkspaceControls();
            if (sessionTitleRename) {
                sessionTitleRename.hidden = !selectedSessionName;
            }
            if (!urlWorkspaceName && !urlProfileName && !urlHomeName) {
                sessionTitle.textContent = `session: ${selectedSessionName || 'No session selected'}`;
                if (messageSessionName) {
                    messageSessionName.textContent = selectedSessionName || 'No session selected';
                }
                updateBrowserTitle();
            }

            for (const session of sessions) {
                const item = document.createElement('li');
                item.className = 'session-item';
                item.classList.toggle('selected', session.name === selected);

                const button = document.createElement('a');
                button.href = maiaUrl(`/session/${encodeURIComponent(session.name)}`);
                button.className = 'sidebar-resource-name';
                button.textContent = session.name;
                button.classList.toggle('selected', session.name === selected);
                button.addEventListener('click', (event) => {
                    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) {
                        return;
                    }
                    event.preventDefault();
                    selectSession(session.name);
                });

                if (urlWorkspaceName && session.workspace === urlWorkspaceName) {
                    item.addEventListener('dragover', (event) => {
                        if (event.dataTransfer?.types.includes('application/x-maia-workspace-file')) {
                            event.preventDefault();
                            if (event.dataTransfer) {
                                event.dataTransfer.dropEffect = 'copy';
                            }
                            item.classList.add('session-drop-target');
                        }
                    });
                    item.addEventListener('dragleave', () => item.classList.remove('session-drop-target'));
                    item.addEventListener('drop', (event) => {
                        event.preventDefault();
                        item.classList.remove('session-drop-target');
                        let paths = [];
                        const encodedPaths = event.dataTransfer?.getData('application/x-maia-workspace-files') || '';
                        if (encodedPaths !== '') {
                            try {
                                const decodedPaths = JSON.parse(encodedPaths);
                                if (Array.isArray(decodedPaths)) {
                                    paths = decodedPaths.filter((path) => typeof path === 'string' && path !== '');
                                }
                            } catch (_) {
                                paths = [];
                            }
                        }
                        if (paths.length === 0) {
                            const path = event.dataTransfer?.getData('application/x-maia-workspace-file') || '';
                            if (path !== '') {
                                paths = [path];
                            }
                        }
                        if (paths.length > 0) {
                            addWorkspaceFilesToSession(paths, session.name);
                        }
                    });
                }

                const remove = document.createElement('button');
                remove.type = 'button';
                remove.className = 'session-delete';
                remove.textContent = '\u00D7';
                remove.title = `Permanently delete session ${session.name}`;
                remove.setAttribute('aria-label', `Permanently delete session ${session.name}`);
                remove.addEventListener('click', (event) => {
                    event.stopPropagation();
                    deleteSession(session.name, remove);
                });

                const rename = document.createElement('button');
                rename.type = 'button';
                rename.className = 'session-rename';
                rename.textContent = '\u270E';
                rename.title = `Rename session ${session.name}`;
                rename.setAttribute('aria-label', `Rename session ${session.name}`);
                rename.addEventListener('click', (event) => {
                    event.stopPropagation();
                    openSessionRename(session.name);
                });

                const settings = document.createElement('button');
                settings.type = 'button';
                settings.className = 'sidebar-settings';
                settings.textContent = '\u2699\uFE0E';
                settings.title = `Settings for session ${session.name}`;
                settings.setAttribute('aria-label', `Settings for session ${session.name}`);
                settings.addEventListener('click', (event) => {
                    event.stopPropagation();
                    openSessionSettings(session.name);
                });

                const copy = document.createElement('button');
                copy.type = 'button';
                copy.className = 'session-copy';
                copy.textContent = '⧉';
                copy.title = `Copy session ${session.name}`;
                copy.setAttribute('aria-label', `Copy session ${session.name}`);
                copy.addEventListener('click', (event) => {
                    event.stopPropagation();
                    openSessionCopy(session.name);
                });

                const actions = document.createElement('div');
                actions.className = 'session-item-actions';
                const actionsToggle = document.createElement('button');
                actionsToggle.type = 'button';
                actionsToggle.className = 'session-item-actions-toggle';
                actionsToggle.textContent = '\u2630';
                actionsToggle.title = `Actions for session ${session.name}`;
                actionsToggle.setAttribute('aria-label', `Actions for session ${session.name}`);
                actionsToggle.setAttribute('aria-haspopup', 'menu');
                actionsToggle.setAttribute('aria-expanded', 'false');

                const actionsMenu = document.createElement('div');
                actionsMenu.className = 'session-item-actions-menu';
                actionsMenu.setAttribute('role', 'menu');
                actionsMenu.hidden = true;
                sessionActionMenuContexts.set(actionsMenu, { parent: actions, toggle: actionsToggle });
                const addMenuAction = (actionButton, description) => {
                    const icon = actionButton.textContent;
                    actionButton.replaceChildren(
                        document.createTextNode(icon),
                        document.createTextNode(` ${description}`)
                    );
                    actionButton.setAttribute('role', 'menuitem');
                    actionButton.addEventListener('click', () => {
                        actionsMenu.hidden = true;
                        actionsToggle.setAttribute('aria-expanded', 'false');
                    });
                    actionsMenu.appendChild(actionButton);
                };
                addMenuAction(rename, 'Rename');
                addMenuAction(settings, 'Settings');
                addMenuAction(copy, 'Copy');
                addMenuAction(remove, 'Delete');
                actionsToggle.addEventListener('click', (event) => {
                    event.stopPropagation();
                    const expanded = actionsMenu.hidden;
                    closeAllSessionActionMenus();
                    if (!expanded) return;
                    actionsMenu.hidden = false;
                    actionsMenu.classList.add('session-item-actions-menu-floating');
                    document.body.appendChild(actionsMenu);
                    actionsToggle.setAttribute('aria-expanded', 'true');
                    positionFloatingMenu(actionsMenu, actionsToggle);
                });
                actions.append(actionsToggle, actionsMenu);
                item.append(button, actions);
                sessionList.appendChild(item);
            }

            updateSessionSearchAction();
            if (sidebar.classList.contains('open')) {
                requestAnimationFrame(revealSelectedSidebarItems);
            }
        }

        function confirmSessionDelete(name) {
            sessionDeleteMessage.textContent = `Permanently delete session “${name}”? Its history and other session data will be removed and cannot be recovered.`;
            sessionDeleteDialog.showModal();

            return new Promise((resolve) => {
                sessionDeleteDialog.addEventListener('close', () => {
                    resolve(sessionDeleteDialog.returnValue === 'delete');
                }, { once: true });
            });
        }

        function openSessionCopy(name) {
            const base = `${name}-copy`;
            let suggested = base;
            let suffix = 2;
            const names = new Set(knownSessions.map((session) => session.name));
            while (names.has(suggested)) {
                suggested = `${base}-${suffix++}`;
            }
            openResourceCreate('session', suggested, true, name);
        }

        function openSessionRename(name) {
            sessionRenameName.value = name;
            sessionRenameError.hidden = true;
            sessionRenameError.textContent = '';
            sessionRenameDialog.dataset.oldName = name;
            sessionRenameDialog.showModal();
            sessionRenameName.focus();
            sessionRenameName.select();
        }

        sessionActionCopy?.addEventListener('click', () => {
            if (selectedSessionName) {
                openSessionCopy(selectedSessionName);
            }
        });

        sessionActionRename?.addEventListener('click', () => {
            if (selectedSessionName) {
                openSessionRename(selectedSessionName);
            }
        });

        sessionTitleRename?.addEventListener('click', () => {
            if (selectedSessionName) {
                openSessionRename(selectedSessionName);
            }
        });

        sessionActionSettings?.addEventListener('click', async () => {
            settingsPanel.showModal();
            settingsToggle.setAttribute('aria-expanded', 'true');
            if (!settingsLoaded) {
                await loadSettings();
            }
        });

        sessionActionDelete?.addEventListener('click', (event) => {
            event.stopPropagation();
            if (selectedSessionName) {
                deleteSession(selectedSessionName, sessionActionDelete);
            }
        });

        compactHistory?.addEventListener('click', () => runWholeHistoryAction(
            'compact',
            'Compact the conversation history? The original entries will be retained as hidden summarized history.',
            compactHistory
        ));

        sessionMoreToggle?.addEventListener('click', (event) => {
            event.stopPropagation();
            const expanded = sessionMoreTools.hidden;
            if (!expanded) {
                closeSessionMoreTools();
                return;
            }
            sessionMoreTools.classList.add('session-more-tools-floating');
            document.body.appendChild(sessionMoreTools);
            sessionMoreTools.hidden = false;
            sessionMoreToggle.setAttribute('aria-expanded', 'true');
            positionFloatingMenu(sessionMoreTools, sessionMoreToggle);
        });

        document.addEventListener('click', (event) => {
            const target = event.target instanceof Element ? event.target : null;
            if (!target?.closest('#session-more-menu, #session-more-tools')) {
                closeSessionMoreTools();
            }
            if (!target?.closest('.session-item-actions, .session-item-actions-menu')) {
                closeAllSessionActionMenus();
            }
        });

        sessionRenameForm?.addEventListener('submit', async (event) => {
            if (event.submitter?.value !== 'rename') {
                return;
            }
            event.preventDefault();
            const oldName = sessionRenameDialog.dataset.oldName || '';
            const newName = sessionRenameName.value.trim();
            sessionRenameError.hidden = true;
            setButtonBusy(sessionRenameSubmit, 'Renaming session...');
            try {
                const response = await fetch('/api/session/rename', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ oldName, newName })
                });
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || 'Unable to rename the session.');
                }

                knownSessions = knownSessions.map((session) =>
                    session.name === oldName ? { ...session, name: newName } : session
                );
                displayedSessions = displayedSessions.map((session) =>
                    session.name === oldName ? { ...session, name: newName } : session
                );
                if (selectedSessionName === oldName) {
                    selectedSessionName = newName;
                    urlSessionName = newName;
                    history.replaceState({}, '', maiaUrl(`/session/${encodeURIComponent(newName)}`));
                    sessionTitle.textContent = `session: ${newName}`;
                    updateBrowserTitle();
                    if (messageSessionName) {
                        messageSessionName.textContent = newName;
                    }
                }
                renderSessions(displayedSessions, selectedSessionName);
                sessionRenameDialog.close('renamed');
            } catch (requestError) {
                sessionRenameError.textContent = requestError.message || 'Unable to rename the session.';
                sessionRenameError.hidden = false;
            } finally {
                clearButtonBusy(sessionRenameSubmit);
            }
        });

        async function deleteSession(name, button) {
            if (!await confirmSessionDelete(name)) {
                return;
            }

            button.disabled = true;
            sessionLoading.hidden = false;
            sessionLoading.lastChild.textContent = 'Deleting session...';
            error.hidden = true;

            try {
                const response = await fetch('/api/session/delete', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'text/plain; charset=utf-8'
                    },
                    body: name
                });
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || 'Unable to delete session.');
                }

                knownSessions = knownSessions.filter((session) => session.name !== name);
                displayedSessions = displayedSessions.filter((session) => session.name !== name);

                if (name === selectedSessionName) {
                    const next = knownSessions[0]?.name;
                    if (next) {
                        await selectSession(next);
                    } else {
                        selectedSessionName = null;
                        renderSessions([], null);
                        history.replaceState({}, '', maiaUrl('/'));
                        showHistoryLoading('No sessions available.');
                    }
                } else {
                    renderSessions(displayedSessions, selectedSessionName);
                }
            } catch (requestError) {
                button.disabled = false;
                sessionLoading.hidden = true;
                showError(requestError.message || 'Unable to delete session.');
            } finally {
                if (name !== selectedSessionName) {
                    sessionLoading.hidden = true;
                }
            }
        }

        function confirmResourceDelete(type, name) {
            const label = type === 'workspace' ? 'workspace' : 'profile';
            resourceDeleteTitle.textContent = `Delete ${label}?`;
            resourceDeleteMessage.textContent = type === 'workspace'
                ? `Permanently delete workspace “${name}”? Its workspace manifest will be removed, but files in its filesystem path will not be deleted.`
                : `Permanently delete profile “${name}”? This cannot be undone.`;
            resourceDeleteDialog.showModal();

            return new Promise((resolve) => {
                resourceDeleteDialog.addEventListener('close', () => {
                    resolve(resourceDeleteDialog.returnValue === 'delete');
                }, { once: true });
            });
        }

        async function deleteResource(type, name, button) {
            if (!await confirmResourceDelete(type, name)) {
                return;
            }

            const endpoints = {
                workspace: '/api/workspace/delete',
                profile: '/api/profile/delete'
            };
            setButtonBusy(button, `Deleting ${type}...`);
            error.hidden = true;
            try {
                const response = await fetch(endpoints[type], {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'text/plain; charset=utf-8'
                    },
                    body: name
                });
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || `Unable to delete the ${type}.`);
                }
                await loadSidebarOptions();
                settingsLoaded = false;
            } catch (requestError) {
                showError(requestError.message || `Unable to delete the ${type}.`);
            } finally {
                clearButtonBusy(button);
            }
        }

        async function openSessionSettings(name) {
            if (name !== selectedSessionName) {
                await selectSession(name);
            }
            setSidebarOpen(false);
            settingsPanel.showModal();
            settingsToggle.setAttribute('aria-expanded', 'true');
            if (!settingsLoaded) {
                await loadSettings();
            }
        }

        async function openResourceSettings(type, name) {
            setLoadingStatus(resourceSettingsStatus, 'Loading settings...');
            resourceSettingsSave.disabled = true;
            resourceSettingsPathLabel.hidden = type !== 'workspace';
            resourceSettingsDescriptionLabel.hidden = type !== 'profile';
            resourceSettingsPath.required = type === 'workspace';
            resourceSettingsTitle.textContent = `${type[0].toUpperCase()}${type.slice(1)} settings: ${name}`;
            resourceSettingsDialog.dataset.type = type;
            resourceSettingsDialog.dataset.name = name;
            resourceSettingsDialog.showModal();
            try {
                const response = await nativeFetch(maiaUrl(`/api/${type}/settings?name=${encodeURIComponent(name)}`));
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || `Unable to load ${type} settings.`);
                }
                resourceSettingsPath.value = result.path || '';
                resourceSettingsDescription.value = result.description || '';
                resourceSettingsStatus.textContent = '';
            } catch (requestError) {
                resourceSettingsStatus.textContent = requestError.message || `Unable to load ${type} settings.`;
            } finally {
                resourceSettingsSave.disabled = false;
            }
        }

        resourceSettingsForm.addEventListener('submit', async (event) => {
            if (event.submitter?.value !== 'save') {
                return;
            }
            event.preventDefault();
            const type = resourceSettingsDialog.dataset.type;
            const name = resourceSettingsDialog.dataset.name;
            const body = type === 'workspace'
                ? { path: resourceSettingsPath.value.trim() }
                : { description: resourceSettingsDescription.value };
            setButtonBusy(resourceSettingsSave, 'Saving settings...');
            setLoadingStatus(resourceSettingsStatus, 'Saving settings...');
            try {
                const response = await nativeFetch(maiaUrl(`/api/${type}/settings?name=${encodeURIComponent(name)}`), {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(body)
                });
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || `Unable to save ${type} settings.`);
                }
                resourceSettingsStatus.textContent = 'Saved.';
                await loadSidebarOptions();
            } catch (requestError) {
                resourceSettingsStatus.textContent = requestError.message || `Unable to save ${type} settings.`;
            } finally {
                clearButtonBusy(resourceSettingsSave);
            }
        });

        function openResourceCreate(type, name = '', editable = false, source = '') {
            resourceCreateError.hidden = true;
            resourceCreateName.value = name;
            resourceCreateName.readOnly = !editable;
            resourceCreatePath.value = '';
            resourceCreateDescription.value = '';

            const labels = {
                session: 'session',
                workspace: 'workspace',
                profile: 'profile'
            };
            resourceCreateTitle.textContent = `Create ${labels[type]}`;
            resourceCreatePathLabel.hidden = type !== 'workspace';
            resourceCreatePath.required = type === 'workspace';
            resourceCreateDescriptionLabel.hidden = type !== 'profile';
            resourceCreateSubmit.disabled = false;
            resourceCreateDialog.dataset.type = type;
            resourceCreateDialog.dataset.source = source;
            if (type === 'session' && source !== '') {
                resourceCreateTitle.textContent = `Copy session '${source}'`;
            }
            resourceCreateDialog.showModal();
        }

        async function createResource(type, name, path = '', description = '') {
            const endpoints = {
                session: '/api/session/create',
                workspace: '/api/workspace/create',
                profile: '/api/profile/create'
            };
            const body = { name };
            if (type === 'session' && resourceCreateDialog.dataset.source) {
                body.source = resourceCreateDialog.dataset.source;
            } else if (type === 'workspace') {
                body.path = path;
            } else if (type === 'profile') {
                body.description = description;
            }

            const endpoint = type === 'profile'
                ? `${endpoints[type]}?scope=${encodeURIComponent(currentContextScope())}`
                : endpoints[type];
            const response = await fetch(endpoint, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(body)
            });
            const result = await response.json();
            if (!response.ok || !result.ok) {
                throw new Error(result.error || `Unable to create ${type}.`);
            }

            resourceCreateDialog.close('created');
            if (type === 'session') {
                sessionSearchInput.value = '';
                await loadSessions();
                await selectSession(name);
            } else {
                await loadSidebarOptions();
                settingsLoaded = false;
            }
        }

        resourceCreateForm.addEventListener('submit', async (event) => {
            if (event.submitter?.value !== 'create') {
                return;
            }
            event.preventDefault();
            const type = resourceCreateDialog.dataset.type;
            const name = resourceCreateName.value.trim();
            const path = resourceCreatePath.value.trim();
            const description = resourceCreateDescription.value;
            setButtonBusy(resourceCreateSubmit, `Creating ${type}...`);
            resourceCreateError.hidden = true;

            try {
                await createResource(type, name, path, description);
            } catch (requestError) {
                resourceCreateError.textContent = requestError.message || `Unable to create ${type}.`;
                resourceCreateError.hidden = false;
            } finally {
                clearButtonBusy(resourceCreateSubmit);
            }
        });

        function resourceSearchSubmit(type) {
            const input = type === 'workspace' ? workspaceSearchInput
                : type === 'profile' ? profileSearchInput : sessionSearchInput;
            const names = type === 'workspace' ? workspaceNames
                : type === 'profile' ? profileNames
                : knownSessions.map((session) => session.name);
            const query = input.value.trim();
            if (query === '') {
                return;
            }
            const exactMatch = names.some((name) => name === query);
            if (!exactMatch && validResourceName(query)) {
                openResourceCreate(type, query);
            }
        }

        workspaceSearchInput.addEventListener('input', () => {
            updateSidebarResourceSearch('workspace');
        });
        profileSearchInput.addEventListener('input', () => {
            updateSidebarResourceSearch('profile');
        });
        sessionCreateAction.addEventListener('click', () => {
            openResourceCreate('session', sessionSearchInput.value.trim());
        });
        workspaceCreateAction.addEventListener('click', () => {
            openResourceCreate('workspace', workspaceSearchInput.value.trim());
        });
        profileCreateAction.addEventListener('click', () => {
            openResourceCreate('profile', profileSearchInput.value.trim());
        });

        workspaceSearch.addEventListener('submit', (event) => {
            event.preventDefault();
            resourceSearchSubmit('workspace');
        });
        profileSearch.addEventListener('submit', (event) => {
            event.preventDefault();
            resourceSearchSubmit('profile');
        });

        let sessionFilterTimer = null;

        function filterSessions(query) {
            sessionLoading.hidden = true;
            error.hidden = true;

            if (query === '') {
                renderSessions(knownSessions, selectedSessionName);
                return;
            }

            let pattern;
            try {
                pattern = new RegExp(query);
            } catch (_) {
                showError('Invalid session regular expression.');
                return;
            }

            const matches = knownSessions.filter((session) => pattern.test(session.name));
            renderSessions(matches, selectedSessionName);
        }

        sessionSearchInput.addEventListener('input', () => {
            updateSessionSearchAction();
            window.clearTimeout(sessionFilterTimer);
            const query = sessionSearchInput.value.trim();
            sessionFilterTimer = window.setTimeout(() => {
                filterSessions(query);
            }, 500);
        });

        sessionSearch.addEventListener('submit', async (event) => {
            event.preventDefault();
            const query = sessionSearchInput.value.trim();
            if (query === '') {
                return;
            }

            const exact = knownSessions.find((session) => session.name === query);
            if (exact) {
                selectSession(exact.name);
                return;
            }

            const exactMatch = knownSessions.some((session) => session.name === query);
            if (!exactMatch && validResourceName(query)) {
                setButtonBusy(sessionSearchAction, 'Creating session...');
                error.hidden = true;
                try {
                    await createResource('session', query);
                } catch (requestError) {
                    showError(requestError.message || 'Unable to create the session.');
                } finally {
                    clearButtonBusy(sessionSearchAction);
                    updateSessionSearchAction();
                }
            }
        });

        function setSelectionBusy(busy) {
            sessionLoading.hidden = !busy;
            sessionList.querySelectorAll('button').forEach((button) => {
                button.disabled = busy;
            });
            sidebarToggle.disabled = busy;
            sidebarClose.disabled = busy;
            if (sessionTitleRename) {
                sessionTitleRename.disabled = busy;
            }
            if (busy) {
                sessionTitle.textContent = 'session: Selecting session...';
                if (messageSessionName) {
                    messageSessionName.textContent = 'Selecting session...';
                }
            }
        }

        async function loadSessions(signal) {
            setLoadingStatus(sessionListPlaceholder, 'Loading sessions...');
            try {
                const response = await fetch('/api/session/list', { signal });
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || 'Unable to load MAIA sessions.');
                }
                knownSessions = result.sessions || [];
                renderSessions(knownSessions, urlWorkspaceName ? null : (urlSessionName || result.selected || null));
                if (workspaceSessionStatus) {
                    workspaceSessionStatus.hidden = true;
                }
            } catch (requestError) {
                sessionListPlaceholder.textContent = requestError.message || 'Unable to load MAIA sessions.';
                sessionListPlaceholder.hidden = false;
                throw requestError;
            }
        }

        async function selectSession(name) {
            error.hidden = true;

            // Resource pages have no session composer. Selecting a session
            // from their sidebar must enter the session page so the session
            // context and composer are rebuilt together.
            if (urlWorkspaceName || urlProfileName || urlHomeName) {
                window.location.href = maiaUrl(`/session/${encodeURIComponent(name)}`);
                return;
            }

            send.disabled = true;
            if (input) {
                input.disabled = true;
            }

            if (selectionController) {
                selectionController.abort();
            }
            const controller = new AbortController();
            selectionController = controller;
            const requestId = ++selectionRequestId;
            setSelectionBusy(true);

            try {
                // The URL is the session selector. No server-side PHP session
                // update is needed; all subsequent API requests carry this name.
                history.pushState({}, '', maiaUrl(`/session/${encodeURIComponent(name)}`));
                urlSessionName = name;
                selectedSessionName = name;
                sessionWorkspaceActive = false;
                workspaceRelativePath = '';
                workspaceEntries = [];
                workspaceSelectedFiles.clear();
                workspaceViewStart = null;
                workspaceViewEnd = null;
                workspaceMarkdownAnchorStart = null;
                workspaceMarkdownAnchorEnd = null;
                if (workspaceFileView) {
                    workspaceFileView.hidden = true;
                    workspaceFileView.dataset.binary = '0';
                }
                if (workspaceFileList) {
                    workspaceFileList.replaceChildren();
                    workspaceFileList.hidden = false;
                }
                if (workspaceFilesPanel) {
                    workspaceFilesPanel.hidden = true;
                    workspaceFilesPanel.classList.remove('workspace-file-page-mode', 'workspace-edit-page-mode');
                }
                if (workspaceFilePath) renderWorkspacePath('');
                if (workspaceFileStatus) {
                    workspaceFileStatus.textContent = '';
                    workspaceFileStatus.classList.remove('error');
                }
                if (filesPanel) filesPanel.hidden = true;
                filesList?.replaceChildren();
                toolPatternList?.replaceChildren();
                skillPatternList?.replaceChildren();
                availableToolsList?.querySelectorAll('li:not(.available-resource-heading)').forEach((item) => item.remove());
                availableSkillsList?.querySelectorAll('li:not(.available-resource-heading)').forEach((item) => item.remove());
                filesToggle?.setAttribute('aria-expanded', 'false');
                filesToggle?.replaceChildren(document.createTextNode('Files ' + String.fromCharCode(0x25B8)));
                workspaceToggle?.setAttribute('aria-expanded', 'false');
                workspaceToggle?.replaceChildren(document.createTextNode('Workspace ' + String.fromCharCode(0x25B8)));
                filesLoaded = false;
                toolsLoaded = false;
                settingsLoaded = false;
                availableToolNames = [];
                availableSkillNames = [];
                updateSessionWorkspaceControls();

                const selectedSessions = knownSessions.map((session) => ({
                    ...session,
                    selected: session.name === name
                }));
                const visibleSessions = displayedSessions.length > 0
                    ? displayedSessions
                    : selectedSessions;
                renderSessions(visibleSessions, name);
                historyItems = [];
                firstIndex = null;
                lastIndex = null;
                showHistoryLoading();
                updateEarlierButton();
                const contextLoads = [
                    loadLastTurn(controller.signal),
                    loadSidebarOptions()
                ];
                if (settingsPanel?.open) {
                    contextLoads.push(loadSettings());
                }
                if (toolsPanel && !toolsPanel.hidden) {
                    contextLoads.push(loadTools());
                }
                if (skillsPanel && !skillsPanel.hidden) {
                    contextLoads.push(loadSkills());
                }
                await Promise.all(contextLoads);
                setSidebarOpen(false);
            } catch (requestError) {
                if (requestError.name !== 'AbortError' && requestId === selectionRequestId) {
                    showError(requestError.message || 'Unable to select MAIA session.');
                }
            } finally {
                if (requestId === selectionRequestId) {
                    selectionController = null;
                    setSelectionBusy(false);
                    if (input) {
                        input.disabled = false;
                        input.focus();
                    }
                    send.disabled = false;
                }
            }
        }

        async function fetchHistory(range, signal) {
            const response = await fetch('/api/history/show', {
                method: 'POST',
                headers: {
                    'Content-Type': 'text/plain; charset=utf-8'
                },
                body: range,
                signal
            });

            const result = await response.json();
            if (!response.ok || !result.ok) {
                throw new Error(result.error || 'Unable to load MAIA history.');
            }

            if (!Array.isArray(result.items)) {
                throw new Error('MAIA returned invalid history items.');
            }

            return result;
        }

        async function loadLastTurn(signal) {
            showHistoryLoading();
            const result = await fetchHistory('turn', signal);
            historyItems = result.items;
            firstIndex = result.firstIndex;
            lastIndex = result.lastIndex;
            renderHistory(historyItems);
            updateEarlierButton();
        }

        async function refreshHistory() {
            if (!historyRefresh || historyRefresh.disabled) {
                return;
            }
            const range = Number.isInteger(Number(firstIndex))
                ? `${Number(firstIndex)}-`
                : 'turn';
            historyRefresh.disabled = true;
            historyRefresh.replaceChildren();
            const spinner = document.createElement('span');
            spinner.className = 'spinner';
            spinner.setAttribute('aria-hidden', 'true');
            historyRefresh.appendChild(spinner);
            historyRefresh.setAttribute('aria-label', 'Refreshing history');
            historyRefresh.title = 'Refreshing history';
            error.hidden = true;
            try {
                const result = await fetchHistory(range);
                historyItems = result.items;
                firstIndex = result.firstIndex;
                lastIndex = result.lastIndex;
                renderHistory(historyItems);
                updateEarlierButton();
            } catch (requestError) {
                showError(requestError.message || 'Unable to refresh MAIA history.');
            } finally {
                historyRefresh.replaceChildren(document.createTextNode('↻'));
                historyRefresh.disabled = false;
                historyRefresh.setAttribute('aria-label', 'Refresh history');
                historyRefresh.title = 'Refresh history';
            }
        }

        historyRefresh?.addEventListener('click', refreshHistory);

        function getTurnCount() {
            const value = turnCount.value.replace(/[^0-9]/g, '').slice(0, 3);
            const count = Math.max(1, Number.parseInt(value || '1', 10));
            turnCount.value = String(count);
            return count;
        }

        turnCount.addEventListener('input', () => {
            turnCount.value = turnCount.value.replace(/[^0-9]/g, '').slice(0, 3);
        });

        async function loadEarlierHistory() {
            if (loadingEarlier) {
                return;
            }

            const userIndexes = historyItems
                .filter((item) => item.role === 'user')
                .map((item) => Number(item.user_index))
                .filter((index) => Number.isInteger(index));
            const earliestUserIndex = userIndexes.length > 0
                ? Math.min(...userIndexes)
                : null;

            if (earliestUserIndex === null || earliestUserIndex <= 0) {
                updateEarlierButton();
                return;
            }

            loadingEarlier = true;
            setButtonBusy(loadEarlier, 'Loading earlier turns...');
            turnCount.disabled = true;
            setLoadingStatus(historyRemaining, 'Loading earlier turns...');
            error.hidden = true;

            const numberOfTurns = getTurnCount();
            const lastPreviousUserIndex = earliestUserIndex - 1;
            const firstPreviousUserIndex = Math.max(0, earliestUserIndex - numberOfTurns);

            try {
                const result = await fetchHistory(
                    `turn${firstPreviousUserIndex}-turn${lastPreviousUserIndex}`
                );
                const earlierItems = result.items;
                if (!earlierItems.some((item) =>
                    item.role === 'user' && Number(item.user_index) === firstPreviousUserIndex
                )) {
                    throw new Error('History user indexes changed while loading earlier turns.');
                }

                historyItems = earlierItems.concat(historyItems);
                firstIndex = Math.min(
                    ...historyItems
                        .map((item) => Number(item.index))
                        .filter((index) => Number.isInteger(index))
                );
                renderHistory(historyItems, false);
                updateEarlierButton();
            } catch (requestError) {
                showError(requestError.message || 'Unable to load the previous turn.');
            } finally {
                loadingEarlier = false;
                clearButtonBusy(loadEarlier);
                turnCount.disabled = false;
                updateEarlierButton();
            }
        }

        async function initialize() {
            if (urlProfileName || urlWorkspaceName || urlHomeName) {
                document.body.classList.add(urlProfileName
                    ? 'profile-page'
                    : (urlWorkspaceName ? 'workspace-page' : 'home-page'));
                const resourceName = urlProfileName || urlWorkspaceName;
                if (resourceName) {
                    if (sessionWorkspacePage) {
                        renderSessionWorkspaceTitle();
                    } else {
                        sessionTitle.textContent = `${urlProfileName ? 'profile' : 'workspace'}: ${resourceName}`;
                    }
                }
                if (urlProfileName) {
                    try {
                        const profileResponse = await fetch(`/api/profile/settings?name=${encodeURIComponent(urlProfileName)}`);
                        const profileResult = await profileResponse.json();
                        if (profileResponse.ok && profileResult.ok && profileResult.scope) {
                            profilePageScope.textContent = `Scope: ${profileResult.scope}`;
                            profilePageScope.hidden = false;
                        }
                    } catch (_) {
                        // The profile page remains usable if scope display fails.
                    }
                }
                if (urlHomeName && profilePageSettings) {
                    profilePageSettings.hidden = true;
                }
                if (profilePageSettings) profilePageSettings.hidden = true;
                if (createProfileButton) createProfileButton.hidden = true;
                if (profileCreateAction) profileCreateAction.hidden = true;
                if (settingsToggle) {
                    settingsToggle.hidden = !(urlProfileName || urlWorkspaceName);
                    if (!settingsToggle.hidden) {
                        settingsToggle.setAttribute('aria-label', urlProfileName ? 'Profile settings' : 'Workspace settings');
                        settingsToggle.title = urlProfileName ? 'Profile settings' : 'Workspace settings';
                    }
                }
                if (filesToggle) filesToggle.hidden = true;
                if (pureWorkspaceBrowserPage) {
                    [settingsToggle, filesToggle, skillsToggle, toolsToggle].forEach((button) => {
                        if (button) button.hidden = true;
                    });
                }
                if (historyRefresh) historyRefresh.hidden = true;
                if (send) send.hidden = true;
                document.querySelector('.history-actions')?.setAttribute('hidden', '');
                conversation.hidden = true;
                error.hidden = true;
                if (urlWorkspaceName && workspaceFileList) {
                    renderWorkspacePath(workspaceRelativePath);
                    workspaceFileUp.disabled = workspaceRelativePath === '';
                    if (initialWorkspacePathType === 'file') {
                        await viewWorkspaceFile({
                            path: workspaceRelativePath,
                            name: workspaceRelativePath.split('/').pop()
                        }, new URLSearchParams(window.location.search).get('edit') === '1');
                    } else if (initialWorkspacePathType === 'directory' || initialWorkspacePathType === 'root') {
                        workspaceFilesPanel?.classList.remove('workspace-file-page-mode', 'workspace-edit-page-mode');
                        workspaceFileList.hidden = false;
                        renderWorkspaceEntries();
                    } else {
                        workspaceFileStatus.textContent = 'The requested workspace path does not exist.';
                        workspaceFileStatus.classList.add('error');
                        workspaceFilesPanel?.classList.remove('workspace-file-page-mode', 'workspace-edit-page-mode');
                        workspaceFileList.hidden = false;
                        renderWorkspaceEntries();
                    }
                    updateWorkspaceBrowserChrome();
                }
                await Promise.allSettled([
                    loadSessions(),
                    loadSidebarOptions(),
                    ...(pureWorkspaceBrowserPage ? [] : [loadTools(), loadSkills()])
                ]);
                return;
            }
            historyClear.hidden = false;
            historyHideLastTurn.hidden = false;
            historyHideAll.hidden = false;
            settingsToggle.hidden = true;
            historyActions.hidden = false;
            showHistoryLoading();
            try {
                await Promise.all([
                    loadSessions(),
                    loadSidebarOptions()
                ]);
                await loadLastTurn();
                send.disabled = false;
                input.focus();
            } catch (requestError) {
                showError(requestError.message || 'Unable to load MAIA history.');
            }
        }

        async function loadEntireHistory() {
            if (loadingEarlier || !Number.isInteger(Number(firstIndex)) || Number(firstIndex) <= 1) {
                return;
            }

            loadingEarlier = true;
            loadEarlier.disabled = true;
            setButtonBusy(loadAllHistory, 'Loading entire history...');
            const originalTitle = loadAllHistory.title;
            loadAllHistory.title = 'Loading entire history...';
            setLoadingStatus(historyRemaining, 'Loading entire history...');
            error.hidden = true;

            try {
                const result = await fetchHistory('all');
                if (result.items.length > 0) {
                    historyItems = result.items.concat(historyItems);
                    firstIndex = Math.min(
                        ...historyItems
                            .map((item) => Number(item.index))
                            .filter((index) => Number.isInteger(index))
                    );
                    renderHistory(historyItems, false);
                }
                updateEarlierButton();
            } catch (requestError) {
                showError(requestError.message || 'Unable to load the entire history.');
            } finally {
                loadingEarlier = false;
                loadEarlier.disabled = false;
                clearButtonBusy(loadAllHistory);
                loadAllHistory.title = originalTitle;
                updateEarlierButton();
            }
        }

        async function runWholeHistoryAction(action, confirmation, triggerButton) {
            if (!window.confirm(confirmation)) {
                return;
            }
            const actionButtons = [historyClear, historyHideLastTurn, historyHideAll];
            for (const button of actionButtons) {
                if (button && button !== triggerButton) button.disabled = true;
            }
            if (triggerButton) {
                setButtonBusy(triggerButton, action === 'compact' ? 'Compacting history...' : 'Updating history...');
            }
            error.hidden = true;
            try {
                const response = await fetch('/api/history/action', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ action })
                });
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || 'Unable to update history.');
                }
                await refreshHistoryAfterMutation();
            } catch (requestError) {
                showError(requestError.message || 'Unable to update history.');
            } finally {
                for (const button of actionButtons) {
                    if (button && button !== triggerButton) button.disabled = false;
                }
                if (triggerButton) clearButtonBusy(triggerButton);
            }
        }

        historyEditForm.addEventListener('submit', async (event) => {
            if (event.submitter?.value !== 'save') {
                return;
            }
            event.preventDefault();
            setButtonBusy(historyEditSubmit, 'Saving entry...');
            historyEditError.hidden = true;
            try {
                await performHistoryAction('replace', { index: historyEditDialog.dataset.index }, historyEditContent.value);
                historyEditDialog.close('saved');
            } catch (requestError) {
                historyEditError.textContent = requestError.message || 'Unable to replace history entry.';
                historyEditError.hidden = false;
            } finally {
                clearButtonBusy(historyEditSubmit);
            }
        });

        historyClear?.addEventListener('click', () => runWholeHistoryAction(
            'clear',
            'Clear the entire history? This cannot be undone.',
            historyClear
        ));
        historyHideLastTurn?.addEventListener('click', () => runWholeHistoryAction(
            'hide-turn',
            'Hide the last turn? It can be unhidden later.',
            historyHideLastTurn
        ));
        historyHideAll?.addEventListener('click', () => runWholeHistoryAction(
            'hide-all',
            'Hide the entire history? It can be unhidden later.',
            historyHideAll
        ));

        loadEarlier?.addEventListener('click', loadEarlierHistory);
        loadAllHistory?.addEventListener('click', loadEntireHistory);

        form.addEventListener('submit', async (event) => {
            event.preventDefault();
            if (!input) {
                return;
            }
            error.hidden = true;

            const message = input.value;
            if (!message.trim()) {
                return;
            }

            const previousLastIndex = Number.isInteger(Number(lastIndex))
                ? Number(lastIndex)
                : null;
            const userItem = {
                role: 'user',
                content: message
            };

            // Display the submitted user item immediately. It is replaced by
            // the persisted history turn after the send has completed.
            historyItems.push(userItem);
            renderHistory(historyItems);
            input.value = '';
            input.disabled = true;
            send.disabled = true;

            const pending = appendMessage('server', '', true);
            updatePendingResponse(pending, 'Waiting for response...');
            let output = '';

            try {
                const response = await fetch('/api/send', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'text/plain; charset=utf-8'
                    },
                    body: message
                });

                // Consume the response stream as it arrives instead of
                // waiting for the complete MAIA process to finish.
                updatePendingResponse(pending, 'Receiving response...');
                if (response.body) {
                    const reader = response.body.getReader();
                    const decoder = new TextDecoder();
                    while (true) {
                        const { value, done } = await reader.read();
                        if (done) {
                            break;
                        }
                        const chunk = decoder.decode(value, { stream: true });
                        const shouldFollow = conversationIsNearBottom();
                        output += chunk;
                        updatePendingResponse(pending, 'Receiving response...', output);
                        if (shouldFollow) {
                            pending.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
                        }
                    }
                    const finalChunk = decoder.decode();
                    output += finalChunk;
                    updatePendingResponse(pending, 'Receiving response...', output);
                } else {
                    output = await response.text();
                    updatePendingResponse(pending, 'Receiving response...', output);
                }

                if (!response.ok) {
                    historyItems = historyItems.filter((item) => item !== userItem);
                    renderHistory(historyItems);
                    appendPartialResponse(output);
                    showError(output || 'The request failed.');
                    return;
                }

                // Keep the streamed raw send output visible while the
                // corresponding persisted history turn is retrieved.
                updatePendingResponse(pending, 'Updating conversation...', output);

                const result = await fetchHistory('turn');
                const returnedFirstIndex = Number(result.firstIndex);
                const historyWasRenumbered = previousLastIndex !== null &&
                    (!Number.isInteger(returnedFirstIndex) ||
                     returnedFirstIndex !== previousLastIndex + 1);

                if (historyWasRenumbered) {
                    // The old indexes can no longer safely identify the
                    // existing items. Start from the freshly retrieved turn.
                    historyItems = result.items;
                } else {
                    const persistedItems = previousLastIndex === null
                        ? []
                        : historyItems.filter((item) => {
                            const index = Number(item.index);
                            return Number.isInteger(index) && index <= previousLastIndex;
                        });
                    historyItems = persistedItems.concat(result.items);
                }

                firstIndex = historyItems.length > 0
                    ? Math.min(...historyItems
                        .map((item) => Number(item.index))
                        .filter((index) => Number.isInteger(index)))
                    : result.firstIndex;
                lastIndex = result.lastIndex;
                renderHistory(historyItems);
                appendPartialResponse(output, conversation.lastElementChild);
                updateEarlierButton();
            } catch (requestError) {
                pending.remove();
                appendPartialResponse(output);
                showError(requestError.message || 'Unable to refresh MAIA history.');
            } finally {
                input.disabled = false;
                send.disabled = false;
                input.focus();
            }
        });

        profilePageSettings?.addEventListener('click', () => openResourceSettings('profile', urlProfileName));
        createProfileButton?.addEventListener('click', () => openResourceCreate('profile', '', true));

        initialize();
    </script>
</body>
</html>
