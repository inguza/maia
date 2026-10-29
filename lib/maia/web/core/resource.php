<?php

declare(strict_types=1);

namespace Maia\Web\Core;

use InvalidArgumentException;

require_once __DIR__ . '/common.php';

/**
 * A web resource with a path relative to the web root.
 *
 * Resource URLs use the single web base path from core/common.php; this is
 * a URL prefix, not a filesystem path.
 */
abstract class Resource
{
    private string $path;

    public function __construct(string $path)
    {
        $path = ltrim(str_replace(chr(92), '/', trim($path)), '/');

        if (
            $path === ''
            || str_contains($path, chr(0))
            || preg_match('~(?:^|/)\.{1,2}(?:/|$)~', $path) === 1
            || preg_match('~^[a-z][a-z0-9+.-]*:~i', $path) === 1
        ) {
            throw new InvalidArgumentException('Resource path must be a local path within the web root.');
        }

        $this->path = $path;
    }

    final public function path(): string
    {
        return $this->path;
    }

    /** A stable key used to deduplicate equivalent resources. */
    abstract public function key(): string;

    /** Render the resource tag using the application's base URI. */
    abstract public function tag(): string;

    final protected function url(): string
    {
        return rtrim(\maia_base_path(), '/') . '/' . $this->path;
    }

    final protected function escape(string $value): string
    {
        return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    }
}

/** A CSS stylesheet resource. */
final class Stylesheet extends Resource
{
    private string $media;

    public function __construct(string $path, string $media = 'all')
    {
        parent::__construct($path);
        $this->media = trim($media);

        if ($this->media === '') {
            throw new InvalidArgumentException('Stylesheet media must not be empty.');
        }
    }

    public function key(): string
    {
        return static::class . ':' . $this->path() . ':' . $this->media;
    }

    public function tag(): string
    {
        return '<link rel="stylesheet" href="'
            . $this->escape($this->url())
            . '" media="'
            . $this->escape($this->media)
            . '">' . PHP_EOL;
    }
}

/** A JavaScript resource. Classic scripts are deferred by default. */
final class Script extends Resource
{
    private bool $module;

    public function __construct(string $path, bool $module = false)
    {
        parent::__construct($path);
        $this->module = $module;
    }

    public function key(): string
    {
        return static::class . ':' . $this->path() . ':' . ($this->module ? 'module' : 'classic');
    }

    public function tag(): string
    {
        $type = $this->module ? ' type="module"' : ' defer';

        return '<script src="'
            . $this->escape($this->url())
            . '"' . $type . '></script>' . PHP_EOL;
    }
}
