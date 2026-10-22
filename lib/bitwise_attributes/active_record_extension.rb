# frozen_string_literal: true

require "active_support/concern"

module BitwiseAttributes
  module ActiveRecordExtension
    extend ActiveSupport::Concern

    class_methods do
      def bitwise_attribute(attribute_name, *keys, aliases: {})
        # C-03: reject empty or duplicate key lists up front
        raise ArgumentError, "#{attribute_name}: at least one key is required" if keys.empty?

        dupes = keys.tally.select { |_, n| n > 1 }.keys
        raise ArgumentError, "#{attribute_name}: duplicate keys #{dupes.inspect}" if dupes.any?

        # C-02: overflow guard — 32-bit INT holds 30 usable bits; BIGINT holds 62
        if keys.size > 62
          raise ArgumentError, "#{attribute_name}: #{keys.size} keys exceeds the 62-bit BIGINT limit"
        elsif keys.size > 30
          warn "[BitwiseAttributes] #{attribute_name} has #{keys.size} keys — use a BIGINT column to avoid overflow"
        end

        invalid_aliases = aliases.values - keys
        raise ArgumentError, "Invalid aliases for #{attribute_name}: #{invalid_aliases}" if invalid_aliases.any?

        bitwise_aliases[attribute_name]    = aliases.with_indifferent_access.freeze
        bitwise_attributes[attribute_name] = keys.map.with_index { |key, index| [key, 1 << index] }
                                                 .to_h.with_indifferent_access.freeze
        define_bitwise_methods(attribute_name, keys)
      end

      def bitwise_aliases
        @bitwise_aliases ||= Hash.new { |h, k| h[k] = {} }
      end

      def bitwise_attributes
        @bitwise_attributes ||= {}
      end

      def inherited(subclass)
        super
        subclass.instance_variable_set(:@bitwise_aliases, bitwise_aliases.dup)
        subclass.instance_variable_set(:@bitwise_attributes, bitwise_attributes.dup)
      end

      def extract_bitmask_keys(attribute_name, attribute_value)
        attribute_value = attribute_value.to_i
        bitwise_attributes[attribute_name].filter { |_key, bit_value| attribute_value & bit_value == bit_value }.keys
      end

      def decode_bitwise_values(attribute_name, bitwise_hash)
        bitwise_mapping = bitwise_attributes[attribute_name]
        bitwise_hash.transform_values do |bitwise_value|
          bitwise_mapping.select { |_key, bit| bitwise_value & bit == bit }.keys
        end
      end

      # G-01: validation macro — ensures the stored integer cannot exceed the declared key space
      def validates_bitwise_attribute(attribute_name, **options)
        max_value = bitwise_attributes.fetch(attribute_name).values.sum
        validates attribute_name,
                  numericality: {
                    only_integer: true,
                    greater_than_or_equal_to: 0,
                    less_than_or_equal_to: max_value
                  },
                  **options
      end

      # G-03: public so instance methods can call it without send
      def normalize_and_fetch_values(attribute_name, keys)
        alias_mappings   = bitwise_aliases[attribute_name]
        attribute_values = bitwise_attributes[attribute_name]
        Array(keys).uniq.map { |key| attribute_values[alias_mappings.fetch(key, key)] }
      end

      private

      def define_bitwise_methods(attribute_name, keys)
        model_class = self # Q-03: capture at definition time; avoids using AR::Relation#model inside lambdas

        define_method(:"#{attribute_name}_values") { self.class.bitwise_attributes[attribute_name] }
        define_method(:"#{attribute_name}_aliases") { self.class.bitwise_aliases[attribute_name] }

        keys.each do |key|
          define_method(:"#{key}_bit?") do
            bit_value = send(:"#{attribute_name}_values")[key]
            (self[attribute_name].to_i & bit_value) != 0 # C-01: .to_i guards against NULL
          end

          define_method(:"set_#{key}_bit") do
            bit_value = send(:"#{attribute_name}_values")[key]
            self[attribute_name] = self[attribute_name].to_i | bit_value # C-01
          end

          define_method(:"unset_#{key}_bit") do
            bit_value = send(:"#{attribute_name}_values")[key]
            self[attribute_name] = self[attribute_name].to_i & ~bit_value # C-01
          end

          # A-02: XOR toggle — the most natural bitwise operation
          define_method(:"toggle_#{key}_bit") do
            bit_value = send(:"#{attribute_name}_values")[key]
            self[attribute_name] = self[attribute_name].to_i ^ bit_value
          end

          define_method(:"#{attribute_name}_#{key}=") do |val|
            send(ActiveModel::Type::Boolean.new.cast(val) ? :"set_#{key}_bit" : :"unset_#{key}_bit")
          end

          define_method(:"#{attribute_name}_#{key}") { send(:"#{key}_bit?") }

          define_method(:"was_previously_#{key}_bit?") do
            bit_value = send(:"#{attribute_name}_values")[key]
            (attribute_previously_was(attribute_name).to_i & bit_value) != 0 # C-01
          end
        end

        define_method(:"set_#{attribute_name}") { |*ks| update_bitwise_attribute(attribute_name, ks, :add) }
        define_method(:"unset_#{attribute_name}") { |*ks| update_bitwise_attribute(attribute_name, ks, :remove) }

        define_method(:"associated_#{attribute_name}") do
          send(:"#{attribute_name}_values").reject { |_key, bit| (self[attribute_name].to_i & bit).zero? }.keys # C-01
        end

        # A-04: assign the full flag set from an array or pass an integer through directly
        define_method(:"#{attribute_name}=") do |value|
          self[attribute_name] =
            case value
            when Integer  then value
            when Array    then self.class.send(:calculate_bitmask, attribute_name, value.map(&:to_s))
            when NilClass then 0
            else raise ArgumentError, "Expected Integer or Array for #{attribute_name}, got #{value.class}"
            end
        end

        # Q-01: quote column name via the adapter; Q-03: use captured model_class, not AR::Relation#model
        scope :"with_#{attribute_name}", lambda { |bit_keys|
          col     = model_class.connection.quote_column_name(attribute_name)
          bitmask = model_class.send(:calculate_bitmask, attribute_name, bit_keys)
          where("#{col} & ? != 0", bitmask)
        }

        # A-01: renamed from with_exact_ — semantics are "has ALL of these bits" (other bits may also be set)
        scope :"with_all_#{attribute_name}", lambda { |bit_keys|
          col     = model_class.connection.quote_column_name(attribute_name)
          bitmask = model_class.send(:calculate_bitmask, attribute_name, bit_keys)
          where("#{col} & :bitmask = :bitmask", { bitmask: bitmask })
        }

        # A-01: true exact equality — column value must equal the bitmask precisely
        scope :"with_exactly_#{attribute_name}", lambda { |bit_keys|
          bitmask = model_class.send(:calculate_bitmask, attribute_name, bit_keys)
          where(attribute_name => bitmask)
        }

        scope :"without_#{attribute_name}", lambda { |bit_keys|
          col     = model_class.connection.quote_column_name(attribute_name)
          bitmask = model_class.send(:calculate_bitmask, attribute_name, bit_keys)
          where("#{col} & ? = 0", bitmask)
        }
      end

      def calculate_bitmask(attribute_name, keys)
        # Q-02: zip so we can report only the unrecognised keys, not the whole input
        unique_keys = Array(keys).uniq
        values      = normalize_and_fetch_values(attribute_name, unique_keys)
        invalid     = unique_keys.zip(values).filter_map { |k, v| k if v.nil? }
        raise ArgumentError, "Unknown #{attribute_name} keys: #{invalid.inspect}" if invalid.any?

        values.sum
      end
    end

    # G-03: direct call — no send needed now that normalize_and_fetch_values is public on the class
    def normalize_and_fetch_values(attribute_name, keys)
      self.class.normalize_and_fetch_values(attribute_name, keys)
    end

    def update_bitwise_attribute(attribute_name, keys, operation)
      bitmask = self.class.send(:calculate_bitmask, attribute_name, keys)
      self[attribute_name] =
        if operation == :add
          self[attribute_name].to_i | bitmask   # C-01
        else
          self[attribute_name].to_i & ~bitmask  # C-01
        end
    end

    private :update_bitwise_attribute # A-03: internal helper — not part of the public instance API
  end
end
