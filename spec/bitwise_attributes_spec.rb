# frozen_string_literal: true

RSpec.describe BitwiseAttributes do
  describe ".bitwise_attribute" do
    it "assigns bit positions in declaration order (1, 2, 4, …)" do
      expect(User.bitwise_attributes[:permissions]).to eq(
        "read" => 1, "write" => 2, "admin" => 4
      )
    end

    it "stores aliases with indifferent access" do
      expect(User.bitwise_aliases[:flags]["confirmed"]).to eq(:verified)
      expect(User.bitwise_aliases[:flags][:confirmed]).to eq(:verified)
    end

    it "freezes the key mapping so it cannot be mutated at runtime" do
      expect(User.bitwise_attributes[:permissions]).to be_frozen
    end

    context "input validation (C-03)" do
      it "raises when no keys are given" do
        expect do
          Class.new(ActiveRecord::Base) do
            self.table_name = "users"
            include BitwiseAttributes
            bitwise_attribute :permissions
          end
        end.to raise_error(ArgumentError, /at least one key is required/)
      end

      it "raises when duplicate keys are given" do
        expect do
          Class.new(ActiveRecord::Base) do
            self.table_name = "users"
            include BitwiseAttributes
            bitwise_attribute :permissions, :read, :write, :read
          end
        end.to raise_error(ArgumentError, /duplicate keys/)
      end

      it "raises when an alias targets a key not in the definition" do
        expect do
          Class.new(ActiveRecord::Base) do
            self.table_name = "users"
            include BitwiseAttributes
            bitwise_attribute :permissions, :read, :write, aliases: { su: :nonexistent }
          end
        end.to raise_error(ArgumentError, /Invalid aliases/)
      end
    end

    context "overflow guard (C-02)" do
      it "raises when key count exceeds 62" do
        expect do
          Class.new(ActiveRecord::Base) do
            self.table_name = "users"
            include BitwiseAttributes
            bitwise_attribute :permissions, *(1..63).map { |i| :"f#{i}" }
          end
        end.to raise_error(ArgumentError, /exceeds the 62-bit BIGINT limit/)
      end

      it "warns when key count exceeds 30" do
        expect do
          Class.new(ActiveRecord::Base) do
            self.table_name = "users"
            include BitwiseAttributes
            bitwise_attribute :permissions, *(1..31).map { |i| :"f#{i}" }
          end
        end.to output(/use a BIGINT column/).to_stderr
      end
    end
  end

  describe "#[attribute]_values and #[attribute]_aliases" do
    subject(:user) { User.new }

    it "returns the bit mapping on the instance" do
      expect(user.permissions_values).to eq("read" => 1, "write" => 2, "admin" => 4)
    end

    it "returns the alias mapping on the instance" do
      expect(user.flags_aliases["confirmed"]).to eq(:verified)
    end
  end

  describe "nil safety (C-01)" do
    it "does not raise when the attribute is NULL" do
      user = User.new
      expect { user.opt_a_bit? }.not_to raise_error
      expect(user.opt_a_bit?).to be false
    end

    it "treats NULL as zero in associated_*" do
      user = User.new
      expect(user.associated_nullable_perms).to eq([])
    end

    it "does not raise in was_previously_*_bit? before the first save" do
      user = User.create!
      expect { user.was_previously_opt_a_bit? }.not_to raise_error
    end

    it "does not raise in set / unset when attribute is NULL" do
      user = User.new
      expect { user.set_opt_a_bit }.not_to raise_error
      expect(user.opt_a_bit?).to be true
    end
  end

  describe "per-flag bit methods" do
    subject(:user) { User.new(permissions: 0) }

    describe "#[key]_bit?" do
      it "returns false when the bit is not set" do
        expect(user.read_bit?).to be false
      end

      it "returns true when the bit is set" do
        user.permissions = 1
        expect(user.read_bit?).to be true
      end

      it "is independent of unrelated bits" do
        user.permissions = 6 # write(2) + admin(4)
        expect(user.read_bit?).to be false
        expect(user.write_bit?).to be true
        expect(user.admin_bit?).to be true
      end
    end

    describe "#set_[key]_bit and #unset_[key]_bit" do
      it "sets a single bit without disturbing others" do
        user.permissions = 2
        user.set_read_bit
        expect(user.permissions).to eq(3)
      end

      it "unsets a single bit without disturbing others" do
        user.permissions = 7
        user.unset_write_bit
        expect(user.permissions).to eq(5)
      end

      it "is idempotent: setting an already-set bit changes nothing" do
        user.permissions = 1
        user.set_read_bit
        expect(user.permissions).to eq(1)
      end

      it "is idempotent: unsetting an already-clear bit changes nothing" do
        user.permissions = 0
        user.unset_read_bit
        expect(user.permissions).to eq(0)
      end
    end

    describe "#toggle_[key]_bit (A-02)" do
      it "sets the bit when it was clear" do
        user.permissions = 0
        user.toggle_read_bit
        expect(user.read_bit?).to be true
      end

      it "clears the bit when it was set" do
        user.permissions = 1
        user.toggle_read_bit
        expect(user.read_bit?).to be false
      end

      it "does not disturb other bits" do
        user.permissions = 6 # write + admin
        user.toggle_read_bit
        expect(user.permissions).to eq(7)
        user.toggle_read_bit
        expect(user.permissions).to eq(6)
      end
    end
  end

  describe "boolean getter and setter (#[attribute]_[key] and #[attribute]_[key]=)" do
    subject(:user) { User.new(permissions: 0) }

    it "getter returns false when the bit is clear" do
      expect(user.permissions_read).to be false
    end

    it "getter returns true when the bit is set" do
      user.permissions = 1
      expect(user.permissions_read).to be true
    end

    it "setter accepts truthy values to set the bit" do
      user.permissions_write = true
      expect(user.write_bit?).to be true
    end

    it "setter accepts falsy values to unset the bit" do
      user.permissions = 3
      user.permissions_write = false
      expect(user.permissions).to eq(1)
    end
  end

  describe "#[attribute]= array setter (A-04)" do
    subject(:user) { User.new(permissions: 0) }

    it "accepts an array and converts it to a bitmask" do
      user.permissions = %i[read admin]
      expect(user.permissions).to eq(5)
    end

    it "accepts an empty array and sets to 0" do
      user.permissions = 7
      user.permissions = []
      expect(user.permissions).to eq(0)
    end

    it "passes an integer through unchanged" do
      user.permissions = 3
      expect(user.permissions).to eq(3)
    end

    it "treats nil as 0" do
      user.permissions = 7
      user.permissions = nil
      expect(user.permissions).to eq(0)
    end

    it "raises ArgumentError for unsupported types" do
      expect { user.permissions = "bad" }.to raise_error(ArgumentError, /Expected Integer or Array/)
    end

    it "works with constructor kwargs" do
      u = User.new(permissions: %i[read write])
      expect(u.permissions).to eq(3)
    end
  end

  describe "#set_[attribute] and #unset_[attribute] (bulk operations)" do
    subject(:user) { User.new(permissions: 0) }

    it "sets multiple bits at once" do
      user.set_permissions(:read, :admin)
      expect(user.permissions).to eq(5)
    end

    it "leaves already-set bits intact when setting" do
      user.permissions = 2
      user.set_permissions(:read)
      expect(user.permissions).to eq(3)
    end

    it "unsets multiple bits at once" do
      user.permissions = 7
      user.unset_permissions(:read, :write)
      expect(user.permissions).to eq(4)
    end

    it "leaves unrelated bits intact when unsetting" do
      user.permissions = 7
      user.unset_permissions(:admin)
      expect(user.permissions).to eq(3)
    end

    it "raises ArgumentError naming only the invalid keys (Q-02)" do
      expect { user.set_permissions(:superadmin) }
        .to raise_error(ArgumentError, /Unknown permissions keys:.*superadmin/)
    end
  end

  describe "#update_bitwise_attribute is private (A-03)" do
    it "is not part of the public interface" do
      expect(User.new).not_to respond_to(:update_bitwise_attribute)
    end
  end

  describe "#associated_[attribute]" do
    it "returns an empty array when no bits are set" do
      expect(User.new(permissions: 0).associated_permissions).to eq([])
    end

    it "returns only the keys whose bits are set" do
      expect(User.new(permissions: 5).associated_permissions).to match_array(%w[read admin])
    end

    it "returns all keys when every bit is set" do
      expect(User.new(permissions: 7).associated_permissions).to match_array(%w[read write admin])
    end
  end

  describe ".extract_bitmask_keys" do
    it "decodes a bitmask integer into the corresponding key names" do
      expect(User.extract_bitmask_keys(:permissions, 5)).to match_array(%w[read admin])
    end

    it "returns an empty array for 0" do
      expect(User.extract_bitmask_keys(:permissions, 0)).to eq([])
    end

    it "accepts string integers" do
      expect(User.extract_bitmask_keys(:permissions, "3")).to match_array(%w[read write])
    end
  end

  describe ".decode_bitwise_values" do
    it "maps a hash of {id => bitmask} to {id => [keys]}" do
      result = User.decode_bitwise_values(:permissions, { 1 => 1, 2 => 6, 3 => 0 })
      expect(result[1]).to match_array(["read"])
      expect(result[2]).to match_array(%w[write admin])
      expect(result[3]).to eq([])
    end
  end

  describe ".validates_bitwise_attribute (G-01)" do
    let(:model_class) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "users"
        include BitwiseAttributes
        bitwise_attribute :permissions, :read, :write, :admin
        validates_bitwise_attribute :permissions
      end
    end

    it "is valid when the value is within range" do
      expect(model_class.new(permissions: 7)).to be_valid
    end

    it "is valid for zero" do
      expect(model_class.new(permissions: 0)).to be_valid
    end

    it "is invalid when the value exceeds the maximum bitmask" do
      expect(model_class.new(permissions: 8)).not_to be_valid
    end

    it "is invalid for negative values" do
      expect(model_class.new(permissions: -1)).not_to be_valid
    end

    it "forwards extra options (e.g. allow_nil)" do
      klass = Class.new(ActiveRecord::Base) do
        self.table_name = "users"
        include BitwiseAttributes
        bitwise_attribute :nullable_perms, :opt_a, :opt_b
        validates_bitwise_attribute :nullable_perms, allow_nil: true
      end
      expect(klass.new(nullable_perms: nil)).to be_valid
    end
  end

  describe "#was_previously_[key]_bit?" do
    it "reflects the bit state before the most recent save" do
      user = User.create!(permissions: 1)
      user.update!(permissions: 0)
      expect(user.was_previously_read_bit?).to be true
    end

    it "returns false when the bit was not set before the save" do
      user = User.create!(permissions: 0)
      user.update!(permissions: 1)
      expect(user.was_previously_read_bit?).to be false
    end
  end

  describe "query scopes" do
    let!(:none)       { User.create!(permissions: 0) }
    let!(:read_only)  { User.create!(permissions: 1) }
    let!(:read_write) { User.create!(permissions: 3) }
    let!(:all_perms)  { User.create!(permissions: 7) }

    describe ".with_[attribute]" do
      it "returns records that have ANY of the specified bits set" do
        expect(User.with_permissions(:admin)).to contain_exactly(all_perms)
      end

      it "returns records matching at least one of multiple keys" do
        expect(User.with_permissions(%i[write admin])).to contain_exactly(read_write, all_perms)
      end

      it "excludes records with none of the bits set" do
        expect(User.with_permissions(:read)).not_to include(none)
      end
    end

    describe ".with_all_[attribute] (A-01 rename)" do
      it "returns records where ALL specified bits are set (other bits may also be set)" do
        result = User.with_all_permissions(%i[read write])
        expect(result).to contain_exactly(read_write, all_perms)
      end

      it "does not return records missing any of the specified bits" do
        expect(User.with_all_permissions(%i[read write])).not_to include(read_only)
      end
    end

    describe ".with_exactly_[attribute] (A-01 new scope)" do
      it "returns only records where the column value equals the bitmask exactly" do
        expect(User.with_exactly_permissions(%i[read write])).to contain_exactly(read_write)
      end

      it "excludes records that have additional bits set" do
        expect(User.with_exactly_permissions(%i[read write])).not_to include(all_perms)
      end
    end

    describe ".without_[attribute]" do
      it "returns records that have NONE of the specified bits set" do
        expect(User.without_permissions(:admin)).to contain_exactly(none, read_only, read_write)
      end

      it "excludes records with even one of the specified bits" do
        expect(User.without_permissions(%i[read write])).to contain_exactly(none)
      end
    end
  end

  describe "aliases" do
    subject(:user) { User.new(flags: 0) }

    it "resolves aliases in bulk set" do
      user.set_flags(:confirmed)
      expect(user.verified_bit?).to be true
    end

    it "resolves aliases in bulk unset" do
      user.flags = 2
      user.unset_flags(:confirmed)
      expect(user.verified_bit?).to be false
    end

    it "resolves aliases in scopes" do
      verified_user = User.create!(flags: 2)
      unverified    = User.create!(flags: 0)

      expect(User.with_flags(:confirmed)).to contain_exactly(verified_user)
      expect(User.without_flags(:confirmed)).to contain_exactly(unverified)
    end

    it "raises ArgumentError naming only the invalid key (Q-02)" do
      expect { user.set_flags(:nonexistent) }
        .to raise_error(ArgumentError, /Unknown flags keys:.*nonexistent/)
    end
  end

  describe "inheritance" do
    let(:subclass) do
      Class.new(User) do
        bitwise_attribute :permissions, :read, :write, :admin, :superadmin
      end
    end

    it "copies the parent's bitwise_attributes to the subclass" do
      expect(subclass.bitwise_attributes[:flags]).to eq(User.bitwise_attributes[:flags])
    end

    it "allows the subclass to extend a redefined attribute independently" do
      expect(subclass.bitwise_attributes[:permissions].keys).to include("superadmin")
    end

    it "does not leak subclass changes back to the parent" do
      expect(User.bitwise_attributes[:permissions].keys).not_to include("superadmin")
    end

    it "copies aliases from the parent" do
      expect(subclass.bitwise_aliases[:flags]["confirmed"]).to eq(:verified)
    end
  end
end
