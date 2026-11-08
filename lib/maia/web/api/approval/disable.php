<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 */

declare(strict_types=1);

require_once __DIR__ . '/common.php';
approval_api_require_post();
approval_api_execute(approval_api_scope(), 'disable', approval_api_rule());
