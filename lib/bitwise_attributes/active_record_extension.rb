# frozen_string_literal: true

require "active_support/concern"

module BitwiseAttributes
  module ActiveRecordExtension
    extend ActiveSupport::Concern

    class_methods do
      # Define a bitwise attribute and dynamically generate methods and scopes
      def bitwise_attribute(attribute_name, *keys, aliases: {})
        invalid_aliases = aliases.values - keys
        raise ArgumentError, "Invalid aliases for #{attribute_name}: #{invalid_aliases}" if invalid_aliases.any?

        bitwise_aliases[attribute_name]     = aliases.with_indifferent_access.freeze
        bitwise_attributes[attribute_name]  = keys.map.with_index { |key, index| [key, 1 << index] }.to_h.with_indifferent_access.freeze
        define_bitwise_methods(attribute_name, keys)
      end

      # Retrieve all defined bitwise aliases
      def bitwise_aliases
        @bitwise_aliases ||= Hash.new { |h, k| h[k] = {} }
      end

      # Retrieve all defined bitwise attributes
      def bitwise_attributes
        @bitwise_attributes ||= {}
      end

      # Ensure inheritance propagates bitwise attributes to subclasses
      def inherited(subclass)
        super

        # Copy bitwise attributes to the subclass
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

      private

      # Dynamically define methods and scopes for a bitwise attribute
      def define_bitwise_methods(attribute_name, keys)
        # Define a method to return the bitwise mapping for this attribute
        define_method(:"#{attribute_name}_values") do
          self.class.bitwise_attributes[attribute_name]
        end

        define_method(:"#{attribute_name}_aliases") do
          self.class.bitwise_aliases[attribute_name]
        end

        # Define methods for individual keys
        keys.each do |key|
          define_method(:"#{key}_bit?") do
            bit_value = send(:"#{attribute_name}_values")[key]
            (self[attribute_name] & bit_value) != 0
          end

          define_method(:"set_#{key}_bit") do
            bit_value = send(:"#{attribute_name}_values")[key]
            self[attribute_name] |= bit_value
          end

          define_method(:"unset_#{key}_bit") do
            bit_value = send(:"#{attribute_name}_values")[key]
            self[attribute_name] &= ~bit_value
          end

          define_method(:"#{attribute_name}_#{key}=") do |val|
            send(ActiveModel::Type::Boolean.new.cast(val) ? :"set_#{key}_bit" : :"unset_#{key}_bit")
          end

          define_method(:"#{attribute_name}_#{key}") do
            send(:"#{key}_bit?")
          end

          define_method(:"was_previously_#{key}_bit?") do
            bit_value = send(:"#{attribute_name}_values")[key]
            (attribute_previously_was(attribute_name) & bit_value) != 0
          end
        end

        # Define helper methods for bulk operations
        define_method(:"set_#{attribute_name}") do |*keys_to_add|
          update_bitwise_attribute(attribute_name, keys_to_add, :add)
        end

        define_method(:"unset_#{attribute_name}") do |*keys_to_remove|
          update_bitwise_attribute(attribute_name, keys_to_remove, :remove)
        end

        # Define method to retrieve associated keys
        define_method(:"associated_#{attribute_name}") do
          send(:"#{attribute_name}_values").reject { |_key, bit| (self[attribute_name] & bit).zero? }.keys
        end

        # Define dynamic scopes for filtering
        scope :"with_#{attribute_name}", lambda { |bit_keys|
          bitmask = model.send(:calculate_bitmask, attribute_name, bit_keys)
          where("#{attribute_name} & ? != 0", bitmask)
        }

        scope :"with_exact_#{attribute_name}", lambda { |bit_keys|
          bitmask = model.send(:calculate_bitmask, attribute_name, bit_keys)
          where("#{attribute_name} & :bitmask = :bitmask", bitmask:)
        }

        scope :"without_#{attribute_name}", lambda { |bit_keys|
          bitmask = model.send(:calculate_bitmask, attribute_name, bit_keys)
          where("#{attribute_name} & ? = 0", bitmask)
        }
      end

      # Calculate the bitmask for given keys (now supports aliases)
      def calculate_bitmask(attribute_name, keys)
        valid_values = normalize_and_fetch_values(attribute_name, keys)
        raise ArgumentError, "Invalid #{attribute_name}: #{keys}" if valid_values.include?(nil)

        valid_values.sum
      end

      def normalize_and_fetch_values(attribute_name, keys)
        alias_mappings    = bitwise_aliases[attribute_name]
        attribute_values  = bitwise_attributes[attribute_name]

        Array(keys).uniq.map { |key| attribute_values[alias_mappings.fetch(key, key)] }
      end
    end

    # Update bitwise attributes for bulk add/remove operations
    def update_bitwise_attribute(attribute_name, keys, operation)
      valid_values = send(:normalize_and_fetch_values, attribute_name, keys)
      raise ArgumentError, "Invalid #{attribute_name}: #{keys}" if valid_values.include?(nil)

      bitmask = valid_values.sum
      self[attribute_name] = operation == :add ? (self[attribute_name] | bitmask) : (self[attribute_name] & ~bitmask)
    end

    def normalize_and_fetch_values(attribute_name, keys)
      self.class.send(:normalize_and_fetch_values, attribute_name, keys)
    end
  end
end
