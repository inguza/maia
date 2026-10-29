<?php
/*
 * Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
 *
 * Licensed under the GNU General Public License v3.0.
 * See LICENSE-GPLv3.txt for the full license text.
 * Commercial licensing is available separately.
 */

declare(strict_types=1);

require_once dirname(__DIR__) . '/core/common.php';
require_once dirname(__DIR__) . '/core/auth.php';

if (!maia_authenticate_page()) {
    exit;
}
