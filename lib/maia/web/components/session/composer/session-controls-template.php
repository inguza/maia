<div class="session-controls">
    <?= $composer ?>
    <div class="panel-group session-panel-toolbar" aria-label="Session panels">
        <?php if ($filesPanel !== ''): ?>
            <?= $filesPanel ?>
        <?php endif; ?>
        <?php if ($changesPanel !== ''): ?>
            <?= $changesPanel ?>
        <?php endif; ?>
        <?php if ($workspacePanel !== ''): ?>
            <?= $workspacePanel ?>
        <?php endif; ?>
        <?= $skillsPanel ?>
        <?= $toolsPanel ?>
        <?php if ($approvalsPanel !== ''): ?>
            <?= $approvalsPanel ?>
        <?php endif; ?>
        <?= $behaviorPanel ?>
        <?= $configurationPanel ?>
    </div>
</div>
