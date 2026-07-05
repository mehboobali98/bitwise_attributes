## [Unreleased]

## [0.1.0] - 2026-07-05

### Added
- `bitwise_attribute` DSL macro to declare bitwise flags on any ActiveRecord model
- Per-flag instance methods: `key_bit?`, `set_key_bit`, `unset_key_bit`
- Boolean getter/setter pair: `attr_key` and `attr_key=` (accepts truthy/falsy values)
- Dirty-tracking predicate: `was_previously_key_bit?`
- Bulk instance methods: `set_attr(*keys)` and `unset_attr(*keys)`
- `associated_attr` to retrieve all currently-set key names as an array
- `attr_values` and `attr_aliases` instance accessors for the mapping and alias hashes
- Class-level `extract_bitmask_keys(attr, integer)` to decode a raw integer into key names
- Class-level `decode_bitwise_values(attr, hash)` to decode a `{id => bitmask}` hash in bulk
- Query scopes: `with_attr`, `with_exact_attr`, `without_attr`
- `aliases:` keyword on `bitwise_attribute` to define alternative names for existing keys; aliases are resolved transparently in all scopes and bulk operations
- Inheritance support: subclasses receive a copy of the parent's bitwise attributes and aliases, and can extend or redefine them independently
- Requires Ruby >= 3.1.4 and Rails >= 6.1.7.3
- CI matrix covering Rails 6.1 / 7.0 / 7.1 / 7.2 on Ruby 3.1–3.3
