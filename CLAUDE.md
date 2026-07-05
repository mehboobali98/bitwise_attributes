# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Install dependencies
bin/setup

# Run all tests and linter (default task)
bundle exec rake

# Run tests only
bundle exec rake spec

# Run a single spec file
bundle exec rspec spec/bitwise_attributes_spec.rb

# Run linter
bundle exec rake rubocop

# Open an interactive console with the gem loaded
bin/console

# Install gem locally
bundle exec rake install

# Release a new version (bumps version.rb, tags, pushes to RubyGems)
bundle exec rake release
```

## Architecture

This is a Ruby gem that adds **bitwise attribute management** to ActiveRecord models via an `ActiveSupport::Concern`.

### How it works

A single integer column stores multiple boolean flags packed as bits. Each flag occupies one bit position (1, 2, 4, 8, …). Defining `bitwise_attribute :permissions, :read, :write, :admin` maps:
- `read` → bit 1
- `write` → bit 2
- `admin` → bit 4

### Key files

- `lib/bitwise_attributes.rb` — Entry point. Includes `ActiveRecordExtension` into the `BitwiseAttributes` concern.
- `lib/bitwise_attributes/active_record_extension.rb` — All the logic: the `bitwise_attribute` DSL macro, dynamically generated instance methods, and ActiveRecord scopes.

### Generated API (per-attribute `attr_name`, per-key `key`)

| Method / Scope | Purpose |
|---|---|
| `key_bit?` | Check if a specific bit is set |
| `set_key_bit` / `unset_key_bit` | Set or clear a single bit |
| `toggle_key_bit` | XOR-flip a single bit |
| `attr_name_key` / `attr_name_key=` | Boolean getter/setter (accepts truthy values) |
| `was_previously_key_bit?` | Dirty-tracking: was bit set before last save |
| `attr_name=` | Assign full flag set from an `Array`, `Integer`, or `nil` |
| `associated_attr_name` | Returns array of all currently-set key names |
| `set_attr_name(*keys)` / `unset_attr_name(*keys)` | Bulk OR-in / AND-NOT-out |
| `validates_bitwise_attribute(attr, **opts)` | Class macro: numericality validation (0..max_bitmask) |
| `with_attr_name(keys)` | Scope: any of the given bits set |
| `with_all_attr_name(keys)` | Scope: all of the given bits set (other bits may also be set) |
| `with_exactly_attr_name(keys)` | Scope: column equals the bitmask exactly |
| `without_attr_name(keys)` | Scope: none of the given bits set |

### Aliases

The `aliases:` keyword lets you define alternative names that map to existing keys:

```ruby
bitwise_attribute :flags, :feature_a, :feature_b, aliases: { fa: :feature_a }
```

Aliases are resolved transparently in scopes and bulk set/unset operations.

### Inheritance

`inherited` hook propagates `@bitwise_attributes` and `@bitwise_aliases` to subclasses via `dup`, so STI subclasses pick up parent definitions and can add their own.

## RuboCop

Configured in `.rubocop.yml`: Ruby 3.1 target, double-quoted strings enforced, max line length 120.
