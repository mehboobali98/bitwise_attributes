# frozen_string_literal: true

require "active_support/concern"
require "active_model/type"

require_relative "bitwise_attributes/version"
require_relative "bitwise_attributes/active_record_extension"

module BitwiseAttributes
  extend ActiveSupport::Concern

  include ActiveRecordExtension
end
