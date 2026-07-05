# frozen_string_literal: true

require "active_record"
require "bitwise_attributes"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

ActiveRecord::Schema.define do
  create_table :users do |t|
    t.integer :permissions, null: false, default: 0
    t.integer :flags, null: false, default: 0
  end

  create_table :employees do |t|
    t.integer :roles, null: false, default: 0
  end
end

class User < ActiveRecord::Base
  include BitwiseAttributes

  bitwise_attribute :permissions, :read, :write, :admin
  bitwise_attribute :flags, :active, :verified, aliases: { confirmed: :verified }
end

class Employee < ActiveRecord::Base
  include BitwiseAttributes

  bitwise_attribute :roles, :manager, :hr, :finance
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.around(:each) do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end
