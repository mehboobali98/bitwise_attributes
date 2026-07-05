## [Unreleased]

## [0.2.0] - 2026-07-05

### Added
- `toggle_key_bit` instance method (XOR) for each defined key
- `with_all_attr(keys)` scope — "all of these bits are set" (any additional bits are also OK)
- `with_exactly_attr(keys)` scope — true exact equality (`WHERE column = bitmask`)
- Array-based setter: `record.attr = [:key_a, :key_b]` computes and assigns the bitmask; `nil` maps to `0`; raw integers pass through unchanged
- `validates_bitwise_attribute(attr, **options)` class macro — adds a numericality validation ensuring the stored integer is between `0` and the maximum possible bitmask for that attribute
- Overflow guard at definition time: raises `ArgumentError` when key count exceeds 62; warns to stderr when it exceeds 30 (recommend BIGINT column)
- Validates that at least one key is provided and that no duplicate keys are present when calling `bitwise_attribute`

### Changed
- `with_exact_attr` renamed to `with_all_attr` — the old name implied exact column equality but the SQL performs a "has all" check; `with_exactly_attr` is the new true-exact scope
- Column names are now quoted via `connection.quote_column_name` in all three SQL scopes for cross-adapter correctness
- Scope lambdas capture the model class at definition time instead of using `ActiveRecord::Relation#model` at query time
- Error messages from invalid key lookups now report only the unrecognised keys, not the full input array
- `normalize_and_fetch_values` is now a public class method (no longer bypassed with `send` from instance context)
- `update_bitwise_attribute` is now a private instance method

### Fixed
- Nil safety: all bitwise operations now call `.to_i` on the raw attribute value, preventing `NoMethodError` when the column is `NULL` or the record is unsaved

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
