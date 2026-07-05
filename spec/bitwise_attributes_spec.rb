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

    it "raises ArgumentError when an alias targets a key not in the definition" do
      expect do
        Class.new(ActiveRecord::Base) do
          self.table_name = "users"
          include BitwiseAttributes
          bitwise_attribute :permissions, :read, :write, aliases: { su: :nonexistent }
        end
      end.to raise_error(ArgumentError, /Invalid aliases/)
    end

    it "freezes the key mapping so it cannot be mutated at runtime" do
      expect(User.bitwise_attributes[:permissions]).to be_frozen
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
        user.permissions = 2 # write
        user.set_read_bit
        expect(user.permissions).to eq(3)
      end

      it "unsets a single bit without disturbing others" do
        user.permissions = 7 # all bits
        user.unset_write_bit
        expect(user.permissions).to eq(5) # read(1) + admin(4)
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

      user2 = User.new(permissions: 0)
      user2.permissions_admin = 1
      expect(user2.admin_bit?).to be true
    end

    it "setter accepts falsy values to unset the bit" do
      user.permissions = 3 # read + write
      user.permissions_write = false
      expect(user.permissions).to eq(1)

      user.permissions_read = nil
      expect(user.permissions).to eq(0)
    end
  end

  describe "#set_[attribute] and #unset_[attribute] (bulk operations)" do
    subject(:user) { User.new(permissions: 0) }

    it "sets multiple bits at once" do
      user.set_permissions(:read, :admin)
      expect(user.permissions).to eq(5) # 1 + 4
    end

    it "leaves already-set bits intact when setting" do
      user.permissions = 2 # write
      user.set_permissions(:read)
      expect(user.permissions).to eq(3)
    end

    it "unsets multiple bits at once" do
      user.permissions = 7 # all
      user.unset_permissions(:read, :write)
      expect(user.permissions).to eq(4)
    end

    it "leaves unrelated bits intact when unsetting" do
      user.permissions = 7
      user.unset_permissions(:admin)
      expect(user.permissions).to eq(3)
    end

    it "raises ArgumentError for an unrecognised key" do
      expect { user.set_permissions(:superadmin) }.to raise_error(ArgumentError, /Invalid permissions/)
    end

    it "raises ArgumentError when unsetting an unrecognised key" do
      expect { user.unset_permissions(:superadmin) }.to raise_error(ArgumentError, /Invalid permissions/)
    end
  end

  describe "#associated_[attribute]" do
    it "returns an empty array when no bits are set" do
      expect(User.new(permissions: 0).associated_permissions).to eq([])
    end

    it "returns only the keys whose bits are set" do
      user = User.new(permissions: 5) # read(1) + admin(4)
      expect(user.associated_permissions).to match_array(["read", "admin"])
    end

    it "returns all keys when every bit is set" do
      user = User.new(permissions: 7)
      expect(user.associated_permissions).to match_array(["read", "write", "admin"])
    end
  end

  describe ".extract_bitmask_keys" do
    it "decodes a bitmask integer into the corresponding key names" do
      expect(User.extract_bitmask_keys(:permissions, 5)).to match_array(["read", "admin"])
    end

    it "returns an empty array for 0" do
      expect(User.extract_bitmask_keys(:permissions, 0)).to eq([])
    end

    it "accepts string integers" do
      expect(User.extract_bitmask_keys(:permissions, "3")).to match_array(["read", "write"])
    end
  end

  describe ".decode_bitwise_values" do
    it "maps a hash of {id => bitmask} to {id => [keys]}" do
      result = User.decode_bitwise_values(:permissions, { 1 => 1, 2 => 6, 3 => 0 })
      expect(result[1]).to match_array(["read"])
      expect(result[2]).to match_array(["write", "admin"])
      expect(result[3]).to eq([])
    end
  end

  describe "#was_previously_[key]_bit?" do
    it "reflects the bit state before the most recent save" do
      user = User.create!(permissions: 1) # read
      user.update!(permissions: 0)        # clear read

      expect(user.was_previously_read_bit?).to be true
    end

    it "returns false when the bit was not set before the save" do
      user = User.create!(permissions: 0)
      user.update!(permissions: 1) # set read

      expect(user.was_previously_read_bit?).to be false
    end
  end

  describe "query scopes" do
    let!(:none)       { User.create!(permissions: 0) }          # no bits
    let!(:read_only)  { User.create!(permissions: 1) }          # read
    let!(:read_write) { User.create!(permissions: 3) }          # read + write
    let!(:all_perms)  { User.create!(permissions: 7) }          # read + write + admin

    describe ".with_[attribute]" do
      it "returns records that have ANY of the specified bits set" do
        result = User.with_permissions(:admin)
        expect(result).to contain_exactly(all_perms)
      end

      it "returns records matching at least one of multiple keys" do
        result = User.with_permissions([:write, :admin])
        expect(result).to contain_exactly(read_write, all_perms)
      end

      it "excludes records with none of the bits set" do
        expect(User.with_permissions(:read)).not_to include(none)
      end
    end

    describe ".with_exact_[attribute]" do
      it "returns only records where ALL specified bits are set (superset match)" do
        result = User.with_exact_permissions([:read, :write])
        expect(result).to contain_exactly(read_write, all_perms)
      end

      it "does not return records missing any of the specified bits" do
        expect(User.with_exact_permissions([:read, :write])).not_to include(read_only)
      end
    end

    describe ".without_[attribute]" do
      it "returns records that have NONE of the specified bits set" do
        result = User.without_permissions(:admin)
        expect(result).to contain_exactly(none, read_only, read_write)
      end

      it "excludes records with even one of the specified bits" do
        result = User.without_permissions([:read, :write])
        expect(result).to contain_exactly(none)
      end
    end
  end

  describe "aliases" do
    subject(:user) { User.new(flags: 0) }

    it "resolves aliases in bulk set" do
      user.set_flags(:confirmed) # alias for :verified
      expect(user.verified_bit?).to be true
    end

    it "resolves aliases in bulk unset" do
      user.flags = 2 # verified(2)
      user.unset_flags(:confirmed)
      expect(user.verified_bit?).to be false
    end

    it "resolves aliases in scopes" do
      verified_user = User.create!(flags: 2)
      unverified    = User.create!(flags: 0)

      expect(User.with_flags(:confirmed)).to contain_exactly(verified_user)
      expect(User.without_flags(:confirmed)).to contain_exactly(unverified)
    end

    it "raises ArgumentError for a key that is neither a defined key nor an alias" do
      expect { user.set_flags(:nonexistent) }.to raise_error(ArgumentError)
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
