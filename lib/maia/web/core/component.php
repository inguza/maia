<?php

declare(strict_types=1);

namespace Maia\Web\Core;

/**
 * A renderable UI component and the resources it requires.
 *
 * Requiring a component file should define its class only. Components are
 * explicitly instantiated and added to a page.
 */
interface Component
{
    /** @return list<Resource> */
    public function resources(): array;

    /** Return this component's HTML markup. */
    public function render(): string;
}
