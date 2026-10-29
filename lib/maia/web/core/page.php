<?php

declare(strict_types=1);

namespace Maia\Web\Core;

use InvalidArgumentException;
use OutOfBoundsException;

require_once __DIR__ . '/resource.php';
require_once __DIR__ . '/component.php';

/**
 * Common page lifecycle: component collection and deduplicated resources.
 * Concrete pages add components and page-specific resources in their constructor.
 */
abstract class Page
{
    /** @var array<string, Component> */
    private array $components = [];

    /** @var array<string, Stylesheet> Insertion-ordered set of stylesheets. */
    private array $stylesheets = [];

    /** @var array<string, Script> Insertion-ordered set of scripts. */
    private array $scripts = [];

    abstract public function title(): string;

    /** CSS class for the document body. */
    public function bodyClass(): string
    {
        return 'page';
    }

    /**
     * Add a component and collect its resources before the layout renders.
     *
     * @throws InvalidArgumentException if the component name is empty or duplicated.
     */
    protected function addComponent(string $name, Component $component): void
    {
        if ($name === '') {
            throw new InvalidArgumentException('Component name must not be empty.');
        }
        if (array_key_exists($name, $this->components)) {
            throw new InvalidArgumentException("Component '{$name}' has already been added.");
        }

        $this->components[$name] = $component;
        $this->addResources($component->resources());
    }

    /** @param list<Resource> $resources */
    protected function addPageResources(array $resources): void
    {
        $this->addResources($resources);
    }

    /** Render a previously added component from a page template. */
    public function renderComponent(string $name): string
    {
        if (!array_key_exists($name, $this->components)) {
            throw new OutOfBoundsException("Component '{$name}' has not been added.");
        }

        return $this->components[$name]->render();
    }

    /** Stylesheet tags for the shared layout's <head>. */
    public function stylesheetTags(): string
    {
        $tags = '';
        foreach ($this->stylesheets as $stylesheet) {
            $tags .= $stylesheet->tag();
        }

        return $tags;
    }

    /** Script tags for the shared layout, normally before </body>. */
    public function scriptTags(): string
    {
        $tags = '';
        foreach ($this->scripts as $script) {
            $tags .= $script->tag();
        }

        return $tags;
    }

    /** @param list<Resource> $resources */
    private function addResources(array $resources): void
    {
        foreach ($resources as $resource) {
            if ($resource instanceof Stylesheet) {
                $this->stylesheets[$resource->key()] ??= $resource;
                continue;
            }
            if ($resource instanceof Script) {
                $this->scripts[$resource->key()] ??= $resource;
                continue;
            }

            throw new InvalidArgumentException(
                'Page resources must be instances of ' . Stylesheet::class . ' or ' . Script::class . '.'
            );
        }
    }
}
