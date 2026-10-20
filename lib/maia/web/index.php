<?php

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
$profilePageName = trim((string) ($_SERVER['MAIA_URL_PROFILE'] ?? ''));
$homePage = trim((string) ($_SERVER['MAIA_URL_HOME'] ?? '')) !== '';
$webBasePath = maia_web_base_path();
$resourcePageName = $workspacePageName !== '' ? $workspacePageName : $profilePageName;
$isResourcePage = $resourcePageName !== '' || $homePage;
$initialSessionName = maia_web_initial_session() ?: 'No session selected';
$initialTitle = $workspacePageName !== ''
    ? 'workspace: ' . $workspacePageName
    : ($profilePageName !== ''
        ? 'profile: ' . $profilePageName
        : ($homePage
            ? 'home: ' . (maia_web_home_dir() ?: 'home')
            : 'session: ' . $initialSessionName));
if (session_status() === PHP_SESSION_ACTIVE) {
    session_write_close();
}

?>
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>MAIA</title>
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
            margin: 0 auto;
            max-width: 60rem;
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

        .session-item > button:first-child {
            flex: 1;
            min-width: 0;
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
            margin-bottom: 0.5rem;
        }

        .history-loading[hidden] {
            display: none;
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

        button {
            font: inherit;
            margin-top: 0.5rem;
            padding: 0.6rem 1rem;
        }

        button:disabled {
            cursor: wait;
            opacity: 0.6;
        }

        .composer-actions {
            align-items: center;
            display: flex;
            justify-content: space-between;
            margin-top: 0.5rem;
        }

        .composer-actions-left {
            display: flex;
            gap: 0.5rem;
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
            padding: 0;
        }

        .files-list li {
            align-items: center;
            display: flex;
            gap: 0.5rem;
            padding: 0.2rem 0;
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

        .available-resource-heading {
            align-items: center;
            color: #6b7280;
            display: flex;
            font-size: 0.8rem;
            font-weight: 600;
            gap: 0.75rem;
            padding: 0.2rem 0;
        }

        .available-resource-heading > :first-child,
        .available-resource-heading > .available-resource-name {
            flex: 1;
            min-width: 0;
        }

        .available-resource-heading > :not(:first-child),
        .available-resource-effects,
        .available-resource-state {
            flex: 0 0 auto;
            white-space: nowrap;
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

        .files-status {
            align-items: center;
            color: #6b7280;
            display: flex;
            font-size: 0.85rem;
            gap: 0.5rem;
            min-height: 1.2rem;
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
            margin: 0;
        }

        .history-actions button[hidden] {
            display: none;
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

        .history-remaining {
            color: #6b7280;
            font-size: 0.85rem;
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
            <button id="sidebar-close" class="sidebar-close" type="button" aria-label="Close sidebar">×</button>
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
            <button id="session-more" class="sidebar-more" type="button" hidden>...</button>
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
                <button type="submit" value="save">Save</button>
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
                    aria-label="Open sidebar" aria-expanded="false">☰</button>
            <h1 id="session-title"><?= escape($initialTitle) ?></h1>
            <span id="profile-page-scope" class="settings-status" hidden></span>
            <button id="create-profile" type="button">Create profile</button>
            <button id="profile-page-settings" class="sidebar-settings" type="button" hidden
                    aria-label="Profile settings">⚙</button>
        </header>

        <div class="history-actions">
            <button id="load-earlier" type="button" hidden>Load previous turns</button>
            <label id="turn-count-control" class="history-turn-count" hidden>
                Turns
                <input id="turn-count" type="text" inputmode="numeric" maxlength="3" value="1"
                       aria-label="Number of previous turns to load">
            </label>
            <span id="history-remaining" class="history-remaining" hidden></span>
            <button id="load-all-history" type="button" hidden>Load entire history</button>
        </div>
        <main id="conversation" class="conversation" aria-live="polite"></main>
        <div id="error" class="error" role="alert" hidden></div>

        <form id="message-form">
<?php if (!$isResourcePage): ?>
            <label for="message">Continue in session: <span id="message-session-name"><?= escape($initialSessionName) ?></span></label>
            <textarea id="message" name="message" required autofocus></textarea>
<?php endif; ?>

            <div class="composer-actions">
                <div class="composer-actions-left">
                    <button id="settings-toggle" type="button"
                            aria-expanded="false">⚙</button>
                    <button id="files-toggle" type="button"
                            aria-expanded="false">Files ▾</button>
                    <button id="skills-toggle" type="button"
                            aria-expanded="false">Skills ▾</button>
                    <button id="tools-toggle" type="button"
                            aria-expanded="false">Tools ▾</button>
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
                <h2>Known files</h2>
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
                <h2>Tools</h2>
                <p id="tools-scope" class="settings-status"></p>
                <div class="file-add">
                    <label class="visually-hidden" for="tool-pattern">Add tool pattern</label>
                    <input id="tool-pattern" type="text" autocomplete="off"
                           placeholder="tool pattern, e.g. * or *:write">
                    <div id="tool-completion-menu" class="file-completion-menu resource-completion-menu" role="listbox" hidden></div>
                    <button id="tool-pattern-add" type="button">Add</button>
                    <button id="tool-clear" type="button">Clear</button>
                    <button id="tool-delete" type="button">Delete</button>
                </div>
                <p id="tools-status" class="files-status" role="status"></p>
                <ul id="tool-pattern-list" class="files-list"></ul>
                <details id="available-tools-details">
                    <summary>Available tools</summary>
                    <ul id="available-tools-list" class="files-list">
                        <li class="available-resource-heading">
                            <span class="available-resource-name">Name - Description</span>
                            <span>Effect</span>
                            <span>Allowed</span>
                        </li>
                    </ul>
                </details>
            </section>

            <section id="skills-panel" class="composer-panel" hidden>
                <h2>Skills</h2>
                <p id="skills-scope" class="settings-status"></p>
                <div class="file-add">
                    <label class="visually-hidden" for="skill-pattern">Add skill pattern</label>
                    <input id="skill-pattern" type="text" autocomplete="off"
                           placeholder="skill pattern, e.g. *">
                    <div id="skill-completion-menu" class="file-completion-menu resource-completion-menu" role="listbox" hidden></div>
                    <button id="skill-pattern-add" type="button">Add</button>
                    <button id="skill-clear" type="button">Clear</button>
                    <button id="skill-delete" type="button">Delete</button>
                </div>
                <p id="skills-status" class="files-status" role="status"></p>
                <ul id="skill-pattern-list" class="files-list"></ul>
                <details id="available-skills-details">
                    <summary>Available skills</summary>
                    <ul id="available-skills-list" class="files-list">
                        <li class="available-resource-heading">
                            <span class="available-resource-name">Name - Description</span>
                            <span>Allowed</span>
                            <span>In memory</span>
                        </li>
                    </ul>
                </details>
            </section>
        </form>
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
                        element.textContent = text;
                    }
                }
            };

            const reportJavaScriptError = (message) => {
                const element = document.getElementById('error');
                if (!element) {
                    return;
                }
                element.textContent = `JavaScript error: ${message}`;
                element.hidden = false;
            };

            window.addEventListener('error', (event) => {
                reportJavaScriptError(event.message || 'Unknown JavaScript error.');
            });
            window.addEventListener('unhandledrejection', (event) => {
                const reason = event.reason instanceof Error
                    ? event.reason.message
                    : String(event.reason || 'Unknown rejected promise.');
                reportJavaScriptError(reason);
            });
            setInitialLoadingState();
        })();
    </script>
    <script>
        const maiaBasePath = <?= json_encode($webBasePath, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) ?>;
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
        const filePath = document.getElementById('file-path');
        const fileCompletionMenu = document.getElementById('file-completion-menu');
        const fileAddButton = document.getElementById('file-add-button');
        const toolsToggle = document.getElementById('tools-toggle');
        const toolsPanel = document.getElementById('tools-panel');
        const skillsToggle = document.getElementById('skills-toggle');
        const skillsPanel = document.getElementById('skills-panel');
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
        const messageSessionName = document.getElementById('message-session-name');
        const sessionList = document.getElementById('session-list');
        const sessionListPlaceholder = document.getElementById('session-list-placeholder');
        const sessionMore = document.getElementById('session-more');
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
        const workspaceList = document.getElementById('workspace-list');
        const workspaceListPlaceholder = document.getElementById('workspace-list-placeholder');
        const profileList = document.getElementById('profile-list');
        const profileListPlaceholder = document.getElementById('profile-list-placeholder');
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

        let urlSessionName = null;
        let urlWorkspaceName = null;
        let urlProfileName = null;
        const maiaPath = maiaBasePath && location.pathname.startsWith(maiaBasePath)
            ? location.pathname.slice(maiaBasePath.length) || '/'
            : location.pathname;
        const urlHomeName = maiaPath === '/home' ? 'home' : null;
        if (maiaPath.startsWith('/workspace/')) {
            try {
                urlWorkspaceName = decodeURIComponent(maiaPath.slice('/workspace/'.length));
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
                urlSessionName = decodeURIComponent(maiaPath.slice('/session/'.length));
            } catch (_) {
                urlSessionName = null;
            }
        }

        const nativeFetch = window.fetch.bind(window);
        window.fetch = (resource, options = {}) => {
            const headers = new Headers(options.headers || {});
            const session = selectedSessionName || urlSessionName;
            if (session) {
                headers.set('X-MAIA-Session', session);
            }
            if (urlWorkspaceName) {
                headers.set('X-MAIA-Workspace', urlWorkspaceName);
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

        function setSidebarOpen(open) {
            document.body.classList.toggle('sidebar-open', open);
            sidebar.classList.toggle('open', open);
            sidebarBackdrop.classList.toggle('visible', open);
            sidebar.setAttribute('aria-hidden', String(!open));
            sidebarToggle.setAttribute('aria-expanded', String(open));
        }

        sidebarToggle.addEventListener('click', () => setSidebarOpen(true));
        sidebarClose.addEventListener('click', () => setSidebarOpen(false));
        sidebarBackdrop.addEventListener('click', () => setSidebarOpen(false));
        document.addEventListener('keydown', (event) => {
            if (event.key === 'Escape') {
                setSidebarOpen(false);
            }
        });

        let settingsLoaded = false;
        let filesLoaded = false;
        let toolsLoaded = false;
        let sidebarOptionsLoaded = false;
        let workspaceNames = [];
        let profileNames = [];
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
                    settings.textContent = '⚙';
                    settings.title = `Settings for ${type} ${name}`;
                    settings.setAttribute('aria-label', `Settings for ${type} ${name}`);
                    settings.addEventListener('click', (event) => {
                        event.stopPropagation();
                        openResourceSettings(type, name);
                    });
                    item.appendChild(settings);
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
                    item.appendChild(remove);
                }
                list.appendChild(item);
            }
        }

        function updateResourceSearchAction(input, action, names, label, createAction) {
            const query = input.value.trim();
            const exactMatch = names.some((name) => name === query);
            const canCreate = query !== '' && !exactMatch && validResourceName(query);
            action.textContent = '🔍';
            action.setAttribute('aria-label', `Search ${label}`);
            if (createAction) {
                createAction.hidden = !canCreate;
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
                renderSidebarNames(workspaceList, workspaceListPlaceholder, workspaceNames, null, workspaceSearchInput.value.trim(), 'workspace');
                updateResourceSearchAction(workspaceSearchInput, workspaceSearchAction, workspaceNames, 'workspace', workspaceCreateAction);
            } else {
                renderSidebarNames(profileList, profileListPlaceholder, profileNames, null, profileSearchInput.value.trim(), 'profile');
                updateResourceSearchAction(profileSearchInput, profileSearchAction, profileNames, 'profile', profileCreateAction);
            }
        }

        async function loadSidebarOptions() {
            try {
                const response = await fetch('/api/session/settings');
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || 'Unable to load workspaces and profiles.');
                }

                workspaceNames = Array.isArray(result.workspaces) ? result.workspaces : [];
                profileNames = Array.isArray(result.profiles) ? result.profiles : [];
                renderSidebarNames(
                    workspaceList,
                    workspaceListPlaceholder,
                    workspaceNames,
                    result.workspace,
                    workspaceSearchInput.value.trim(),
                    'workspace'
                );
                renderSidebarNames(
                    profileList,
                    profileListPlaceholder,
                    profileNames,
                    result.profile,
                    profileSearchInput.value.trim(),
                    'profile'
                );
                updateSidebarResourceSearch('workspace');
                updateSidebarResourceSearch('profile');
                sidebarOptionsLoaded = true;
            } catch (requestError) {
                workspaceListPlaceholder.hidden = false;
                profileListPlaceholder.hidden = false;
                workspaceListPlaceholder.textContent = 'Unable to load workspaces.';
                profileListPlaceholder.textContent = 'Unable to load profiles.';
                sidebarOptionsLoaded = false;
            }
        }

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
            button.disabled = true;
            filesStatus.textContent = `Removing ${file}...`;
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
                button.disabled = false;
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
            settingsStatus.textContent = 'Loading...';
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
            settingsSave.disabled = true;
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
                settingsStatus.textContent = 'Saved.';
                filesLoaded = false;
                if (!filesPanel.hidden) {
                    await loadFiles();
                }
            } catch (requestError) {
                settingsStatus.textContent = requestError.message || 'Unable to save settings.';
            } finally {
                settingsSave.disabled = false;
            }
        });

        filesToggle.addEventListener('click', async () => {
            const expanded = filesPanel.hidden;
            filesPanel.hidden = !expanded;
            filesToggle.setAttribute('aria-expanded', String(expanded));
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

            fileAddButton.disabled = true;
            filePath.disabled = true;
            filesStatus.textContent = 'Adding file...';
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
                fileAddButton.disabled = false;
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
            renderFileCompletionMenu();
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
                    const value = document.createElement('span');
                    value.className = 'known-file-path available-resource-name';
                    value.textContent = tool.description
                        ? `${tool.name} - ${tool.description}`
                        : tool.name;
                    value.title = value.textContent;
                    const effects = document.createElement('span');
                    effects.className = 'settings-status available-resource-effects';
                    effects.textContent = Array.isArray(tool.effects) && tool.effects.length > 0
                        ? tool.effects.join(', ')
                        : '(none)';
                    const state = document.createElement('span');
                    state.textContent = tool.allowed ? 'Yes' : 'No';
                    state.className = 'settings-status available-resource-state';
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

        async function addToolPattern() {
            const pattern = toolPattern.value.trim();
            if (pattern === '') {
                toolsStatus.textContent = 'Enter a tool pattern.';
                toolPattern.focus();
                return;
            }
            toolPatternAdd.disabled = true;
            toolPattern.disabled = true;
            toolsStatus.textContent = 'Adding tool pattern...';
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
                toolPatternAdd.disabled = false;
                toolPattern.disabled = false;
                toolPattern.focus();
            }
        }

        async function removeToolPattern(pattern, button) {
            button.disabled = true;
            toolsStatus.textContent = `Removing ${pattern}...`;
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
                button.disabled = false;
            }
        }

        async function updateToolDefinitions(action, button) {
            if (!window.confirm(action === 'clear'
                ? 'Clear the session tool definitions? This leaves no tools allowed at this scope.'
                : 'Delete the session tool definitions? The effective definition will be inherited from another scope.')) {
                return;
            }
            button.disabled = true;
            toolsStatus.textContent = action === 'clear' ? 'Clearing tool definitions...' : 'Deleting tool definitions...';
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
                button.disabled = false;
            }
        }

        toolClear.addEventListener('click', () => updateToolDefinitions('clear', toolClear));
        toolDelete.addEventListener('click', () => updateToolDefinitions('delete', toolDelete));

        toolsToggle.addEventListener('click', async () => {
            const expanded = toolsPanel.hidden;
            toolsPanel.hidden = !expanded;
            toolsToggle.setAttribute('aria-expanded', String(expanded));
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
            return urlProfileName ? 'profile'
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
                    const value = document.createElement('span');
                    value.className = 'known-file-path available-resource-name';
                    value.textContent = skill.description
                        ? `${skill.name} - ${skill.description}`
                        : skill.name;
                    value.title = value.textContent;
                    const state = document.createElement('span');
                    state.className = 'settings-status available-resource-state';
                    state.textContent = skill.allowed ? 'Yes' : 'No';
                    const memoryLabel = document.createElement('label');
                    memoryLabel.className = 'skill-memory';
                    const checkbox = document.createElement('input');
                    checkbox.type = 'checkbox';
                    checkbox.checked = Boolean(skill.memory);
                    checkbox.disabled = !skill.allowed;
                    checkbox.title = skill.allowed
                        ? 'Load this skill into memory'
                        : 'The skill must be allowed before it can be loaded into memory';
                    checkbox.addEventListener('change', () => updateSkillMemory(skill.name, checkbox));
                    memoryLabel.append(checkbox, document.createTextNode(' In memory'));
                    item.append(value, state, memoryLabel);
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

        async function updateSkillMemory(name, checkbox) {
            const desired = checkbox.checked;
            checkbox.disabled = true;
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
                checkbox.disabled = false;
                skillsStatus.textContent = desired ? `${name} is in memory.` : `${name} removed from memory.`;
            } catch (requestError) {
                checkbox.checked = !desired;
                checkbox.disabled = false;
                skillsStatus.textContent = requestError.message || 'Unable to update skill memory.';
            }
        }

        async function addSkillPattern() {
            const pattern = skillPattern.value.trim();
            if (pattern === '') {
                skillsStatus.textContent = 'Enter a skill pattern.';
                skillPattern.focus();
                return;
            }
            skillPatternAdd.disabled = true;
            skillPattern.disabled = true;
            skillsStatus.textContent = 'Adding skill pattern...';
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
                skillPatternAdd.disabled = false;
                skillPattern.disabled = false;
                skillPattern.focus();
            }
        }

        async function updateSkillContext(action, patternOrButton, maybeButton) {
            const pattern = typeof patternOrButton === 'string' ? patternOrButton : '';
            const button = maybeButton || patternOrButton;
            if (action === 'disable') {
                button.disabled = true;
            } else if (!window.confirm(action === 'clear'
                ? 'Clear the skill definitions at this scope?'
                : 'Delete the skill definitions at this scope?')) {
                return;
            }
            skillsStatus.textContent = `${action === 'disable' ? 'Removing' : action === 'clear' ? 'Clearing' : 'Deleting'} skill definitions...`;
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
                if (action === 'disable') {
                    button.disabled = false;
                }
            }
        }

        skillsToggle.addEventListener('click', async () => {
            const expanded = skillsPanel.hidden;
            skillsPanel.hidden = !expanded;
            skillsToggle.setAttribute('aria-expanded', String(expanded));
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

        function createToolCallElement(name, argumentsText) {
            const element = document.createElement('div');
            element.className = 'tool-call';

            const details = document.createElement('details');
            const summary = document.createElement('summary');
            summary.textContent = `Tool call: ${name}`;

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
                content.textContent = String(item.backup.content);
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
            content.textContent = text;
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
                        content.textContent = String(item.content);
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
            if (isHiddenHistoryItem(item) && conversation.lastElementChild !== elementBefore) {
                conversation.lastElementChild.classList.add('hidden-entry');
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
            summary.textContent = `Show ${items.length} hidden ${items.length === 1 ? 'entry' : 'entries'} · ${turnCount} ${turnCount === 1 ? 'turn' : 'turns'} affected`;

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

            const status = document.createElement('div');
            status.className = 'pending-status';
            const spinner = document.createElement('span');
            spinner.className = 'spinner';
            spinner.setAttribute('aria-hidden', 'true');
            const text = document.createElement('span');
            text.textContent = statusText;
            status.append(spinner, text);
            element.appendChild(status);

            if (output !== '') {
                const content = document.createElement('div');
                content.textContent = output;
                element.appendChild(content);
            }
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
        let visibleSessionCount = 10;
        let selectionController = null;
        let selectionRequestId = 0;

        function renderSessions(sessions, selected) {
            displayedSessions = sessions;
            sessionList.replaceChildren();
            sessionListPlaceholder.textContent = sessions.length > 0
                ? ''
                : 'No matching sessions.';
            sessionListPlaceholder.hidden = sessions.length > 0;

            selectedSessionName = selected || null;
            if (!urlWorkspaceName && !urlProfileName && !urlHomeName) {
                sessionTitle.textContent = `session: ${selectedSessionName || 'No session selected'}`;
                if (messageSessionName) {
                    messageSessionName.textContent = selectedSessionName || 'No session selected';
                }
            }

            for (const session of sessions.slice(0, visibleSessionCount)) {
                const item = document.createElement('li');
                item.className = 'session-item';

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

                const remove = document.createElement('button');
                remove.type = 'button';
                remove.className = 'session-delete';
                remove.textContent = 'X';
                remove.title = `Permanently delete session ${session.name}`;
                remove.setAttribute('aria-label', `Permanently delete session ${session.name}`);
                remove.addEventListener('click', (event) => {
                    event.stopPropagation();
                    deleteSession(session.name, remove);
                });

                const settings = document.createElement('button');
                settings.type = 'button';
                settings.className = 'sidebar-settings';
                settings.textContent = '⚙';
                settings.title = `Settings for session ${session.name}`;
                settings.setAttribute('aria-label', `Settings for session ${session.name}`);
                settings.addEventListener('click', (event) => {
                    event.stopPropagation();
                    openSessionSettings(session.name);
                });

                item.append(button, settings, remove);
                sessionList.appendChild(item);
            }

            sessionMore.hidden = sessions.length <= visibleSessionCount;
            updateSessionSearchAction();
        }

        sessionMore.addEventListener('click', () => {
            visibleSessionCount += 10;
            renderSessions(displayedSessions, selectedSessionName);
        });

        function confirmSessionDelete(name) {
            sessionDeleteMessage.textContent = `Permanently delete session “${name}”? Its history and other session data will be removed and cannot be recovered.`;
            sessionDeleteDialog.showModal();

            return new Promise((resolve) => {
                sessionDeleteDialog.addEventListener('close', () => {
                    resolve(sessionDeleteDialog.returnValue === 'delete');
                }, { once: true });
            });
        }

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
            button.disabled = true;
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
                button.disabled = false;
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
            resourceSettingsStatus.textContent = 'Loading...';
            resourceSettingsPathLabel.hidden = type !== 'workspace';
            resourceSettingsDescriptionLabel.hidden = type !== 'profile';
            resourceSettingsPath.required = type === 'workspace';
            resourceSettingsTitle.textContent = `${type[0].toUpperCase()}${type.slice(1)} settings: ${name}`;
            resourceSettingsDialog.dataset.type = type;
            resourceSettingsDialog.dataset.name = name;
            resourceSettingsDialog.showModal();
            try {
                const response = await fetch(`/api/${type}/settings?name=${encodeURIComponent(name)}`);
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || `Unable to load ${type} settings.`);
                }
                resourceSettingsPath.value = result.path || '';
                resourceSettingsDescription.value = result.description || '';
                resourceSettingsStatus.textContent = '';
            } catch (requestError) {
                resourceSettingsStatus.textContent = requestError.message || `Unable to load ${type} settings.`;
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
            resourceSettingsStatus.textContent = 'Saving...';
            try {
                const response = await fetch(`/api/${type}/settings?name=${encodeURIComponent(name)}`, {
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
            }
        });

        function openResourceCreate(type, name = '', editable = false) {
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
            resourceCreateDialog.showModal();
        }

        async function createResource(type, name, path = '', description = '') {
            const endpoints = {
                session: '/api/session/create',
                workspace: '/api/workspace/create',
                profile: '/api/profile/create'
            };
            const body = { name };
            if (type === 'workspace') {
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
            resourceCreateSubmit.disabled = true;
            resourceCreateError.hidden = true;

            try {
                await createResource(type, name, path, description);
            } catch (requestError) {
                resourceCreateError.textContent = requestError.message || `Unable to create ${type}.`;
                resourceCreateError.hidden = false;
                resourceCreateSubmit.disabled = false;
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
                visibleSessionCount = 10;
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
            visibleSessionCount = 10;
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
                sessionSearchAction.disabled = true;
                error.hidden = true;
                try {
                    await createResource('session', query);
                } catch (requestError) {
                    showError(requestError.message || 'Unable to create the session.');
                } finally {
                    sessionSearchAction.disabled = false;
                    updateSessionSearchAction();
                }
            }
        });

        function setSelectionBusy(busy) {
            sessionLoading.hidden = !busy;
            sessionMore.disabled = busy;
            sessionList.querySelectorAll('button').forEach((button) => {
                button.disabled = busy;
            });
            sidebarToggle.disabled = busy;
            sidebarClose.disabled = busy;
            if (busy) {
                sessionTitle.textContent = 'session: Selecting session...';
                if (messageSessionName) {
                    messageSessionName.textContent = 'Selecting session...';
                }
            }
        }

        async function loadSessions(signal) {
            const response = await fetch('/api/session/list', { signal });
            const result = await response.json();
            if (!response.ok || !result.ok) {
                throw new Error(result.error || 'Unable to load MAIA sessions.');
            }
            knownSessions = result.sessions || [];
            visibleSessionCount = 10;
            renderSessions(knownSessions, result.selected || null);
        }

        async function selectSession(name) {
            error.hidden = true;

            // Resource pages have no session composer. Selecting a session
            // from their sidebar must enter the session page so the session
            // context and composer are rebuilt together.
            if (urlWorkspaceName || urlProfileName) {
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
                filesLoaded = false;
                updateEarlierButton();
                await loadLastTurn(controller.signal);
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
            loadEarlier.disabled = true;
            turnCount.disabled = true;
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
                loadEarlier.disabled = false;
                turnCount.disabled = false;
            }
        }

        async function initialize() {
            if (urlProfileName || urlWorkspaceName || urlHomeName) {
                document.body.classList.add(urlProfileName
                    ? 'profile-page'
                    : (urlWorkspaceName ? 'workspace-page' : 'home-page'));
                const resourceName = urlProfileName || urlWorkspaceName;
                if (resourceName) {
                    sessionTitle.textContent = `${urlProfileName ? 'profile' : 'workspace'}: ${resourceName}`;
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
                if (urlHomeName) {
                    profilePageSettings.hidden = true;
                }
                profilePageSettings.hidden = !urlProfileName;
                settingsToggle.hidden = true;
                filesToggle.hidden = true;
                send.hidden = true;
                document.querySelector('.history-actions')?.setAttribute('hidden', '');
                conversation.hidden = true;
                error.hidden = true;
                await Promise.allSettled([
                    loadSessions(),
                    loadSidebarOptions(),
                    loadTools(),
                    loadSkills()
                ]);
                return;
            }
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
            loadAllHistory.disabled = true;
            const originalText = loadAllHistory.textContent;
            loadAllHistory.textContent = 'Loading entire history...';
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
                loadAllHistory.disabled = false;
                loadAllHistory.textContent = originalText;
            }
        }

        loadEarlier.addEventListener('click', loadEarlierHistory);
        loadAllHistory.addEventListener('click', loadEntireHistory);

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
                let output = '';
                if (response.body) {
                    const reader = response.body.getReader();
                    const decoder = new TextDecoder();
                    while (true) {
                        const { value, done } = await reader.read();
                        if (done) {
                            break;
                        }
                        const chunk = decoder.decode(value, { stream: true });
                        output += chunk;
                        updatePendingResponse(pending, 'Receiving response...', output);
                        pending.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
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
                    pending.remove();
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
                updateEarlierButton();
            } catch (requestError) {
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
