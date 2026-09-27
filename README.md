# BitwiseAttributes

Pack multiple boolean flags into a single integer column on an ActiveRecord model. Each flag occupies one bit, so you get cheap storage and fast bitwise SQL queries with no schema changes per new flag.

On the two years this ran internally before it was published, and what that changed:
[I used it internally for two years before publishing it](https://mehboob.dev/blog/two-years-before-i-published-it).

## Installation

Add to your Gemfile:

```ruby
gem "bitwise_attributes"
```

Or install directly:

```sh
gem install bitwise_attributes
```

## Requirements

- Ruby >= 3.1.4
- Rails (ActiveRecord) >= 6.1.7.3

## Usage

### Setup

Add an integer column to your table (default `0`, not null):

```ruby
add_column :users, :permissions, :integer, null: false, default: 0
```

Include the concern and declare your attribute:

```ruby
class User < ApplicationRecord
  include BitwiseAttributes

  bitwise_attribute :permissions, :read, :write, :admin
end
```

Keys are assigned bit positions in declaration order: `read` → 1, `write` → 2, `admin` → 4.

### Per-flag methods

For each key the following methods are generated (shown for `read`):

```ruby
user.read_bit?                # => true / false
user.set_read_bit             # sets the bit in memory
user.unset_read_bit           # clears the bit in memory
user.toggle_read_bit          # XOR — flips the bit

user.permissions_read         # alias for read_bit?
user.permissions_read = true  # accepts any truthy/falsy value
user.permissions_read = false

user.was_previously_read_bit? # dirty-tracking: state before last save
```

### Bulk operations

```ruby
user.set_permissions(:read, :admin)    # OR-in multiple bits
user.unset_permissions(:write)         # AND-NOT-out multiple bits

user.permissions = [:read, :admin]     # assign the full set from an array
user.permissions = 5                   # raw integer passthrough also accepted

user.associated_permissions            # => ["read", "admin"]
user.permissions_values                # => {"read"=>1, "write"=>2, "admin"=>4}
```

### Validation

```ruby
class User < ApplicationRecord
  include BitwiseAttributes
  bitwise_attribute :permissions, :read, :write, :admin
  validates_bitwise_attribute :permissions            # 0..7, integer only
  validates_bitwise_attribute :flags, allow_nil: true # passes Rails validator options through
end
```

### Scopes

```ruby
User.with_permissions(:read)                    # any of the given bits set
User.with_permissions([:read, :write])

User.with_all_permissions([:read, :write])      # ALL given bits set (other bits may also be set)

User.with_exactly_permissions([:read, :write])  # column = bitmask exactly (no other bits)

User.without_permissions(:admin)                # none of the given bits set
```

### Aliases

Map alternative names to existing keys:

```ruby
bitwise_attribute :flags, :active, :verified, aliases: { confirmed: :verified }

user.set_flags(:confirmed)         # sets :verified bit
User.with_flags(:confirmed)        # same as with_flags(:verified)
```

### Class-level helpers

```ruby
User.extract_bitmask_keys(:permissions, 5)
# => ["read", "admin"]

User.decode_bitwise_values(:permissions, { 1 => 3, 2 => 4 })
# => { 1 => ["read", "write"], 2 => ["admin"] }
```

### Inheritance

Subclasses inherit all bitwise attribute definitions from their parent. Each subclass gets its own independent copy, so adding or redefining an attribute on a subclass does not affect the parent.

```ruby
class AdminUser < User
  bitwise_attribute :permissions, :read, :write, :admin, :superadmin
end

AdminUser.bitwise_attributes[:permissions].keys  # => [..., "superadmin"]
User.bitwise_attributes[:permissions].keys       # unchanged
```

## Development

```sh
bin/setup          # install dependencies
bundle exec rake   # run tests + rubocop
bundle exec rspec  # tests only
bin/console        # interactive prompt with the gem loaded
```

To test against a specific Rails version:

```sh
RAILS_VERSION=6.1 bundle install && bundle exec rake
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/mehboobali98/bitwise_attributes. Contributors are expected to adhere to the [code of conduct](https://github.com/mehboobali98/bitwise_attributes/blob/main/CODE_OF_CONDUCT.md).

## License

Available as open source under the [MIT License](https://opensource.org/licenses/MIT).
