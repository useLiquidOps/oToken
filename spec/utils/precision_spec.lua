local precision = require "utils.precision"
local bint = require "utils.bint"(1024)

describe("Precision tests", function ()
	describe("getPrecision()", function ()
	  it("should return the collateral denomination if it is >18", function ()
			local collateral_denomination = 22
			_G.CollateralDenomination = collateral_denomination

			local res = precision.getPrecision()

			assert.are.equal(collateral_denomination, res)
    end)

		it("should return 18 if the collateral denomination is less than 18", function ()
  		local collateral_denomination = 12
  		_G.CollateralDenomination = collateral_denomination

      local res = precision.getPrecision()

      assert.are.equal(18, res)
		end)
  end)

	describe("getPrecisionDiff()", function ()
		it("should return 0 if the collateral denomination is >18", function ()
  		local collateral_denomination = 22
  		_G.CollateralDenomination = collateral_denomination

      local res = precision.getPrecisionDiff()

      assert.are.equal(0, res)
    end)

		it("should return the correct difference if the collateral denomination is less than 18", function ()
			local collateral_denomination = 12
  		_G.CollateralDenomination = collateral_denomination

      local res = precision.getPrecisionDiff()

      assert.are.equal(18 - collateral_denomination, res)
    end)
  end)

	describe("toInternalPrecision()", function ()
  	local collateral_denomination = 12

    before_each(function ()
  		_G.CollateralDenomination = collateral_denomination
    end)

    it("should return the same native amount if the precision difference is 0", function ()
      local high_denomination = 22
      _G.CollateralDenomination = high_denomination
      local quantity = "538757382957263460"

      local res = precision.toInternalPrecision(quantity)

      assert.are.equal(quantity, res)
    end)

    it("should early return zero for a zero input", function ()
      local res = precision.toInternalPrecision(0)

      assert.are.equal(0, res)
    end)

    it("should return the correct internal precision when there is a precision difference", function ()
      local quantity = "532647801523561"

      local res = precision.toInternalPrecision(quantity)

      assert.are.equal(
        tostring(bint(quantity) * bint.ipow(10, 18 - collateral_denomination)),
        tostring(res)
      )
    end)
  end)

	describe("toNativePrecision()", function ()
		local collateral_denomination = 12

	  before_each(function ()
			_G.CollateralDenomination = collateral_denomination
    end)

		it("should return the same internal amount if the precision difference is 0", function ()
			local high_denomination = 22
			_G.CollateralDenomination = high_denomination
			local quantity = "2256328706923752352361"

			local res_up = precision.toNativePrecision(
	      quantity,
				"roundup"
			)
			local res_down = precision.toNativePrecision(
	      quantity,
				"rounddown"
			)

			assert.are.equal(quantity, tostring(res_up))
			assert.are.equal(quantity, tostring(res_down))
    end)

		it("should early return zero for a zero input", function ()
			local res = precision.toNativePrecision(0, "roundup")

			assert.are.equal(0, res)
    end)

		it("should return the correct rounded up quantity", function ()
			local expected_quantity = "2152356326"
			local internal_quantity = tostring((bint(expected_quantity) - bint.one()) * bint.ipow(10, 18 - collateral_denomination) + bint.one())

			local res = precision.toNativePrecision(internal_quantity, "roundup")

			assert.are.equal(expected_quantity, tostring(res))
    end)

		it("should return the correct rounded down quantity", function ()
			local expected_quantity = "5832986623"
			local internal_quantity = tostring(bint(expected_quantity) * bint.ipow(10, 18 - collateral_denomination) + bint(string.rep("9", 18 - collateral_denomination)))

			local res = precision.toNativePrecision(internal_quantity, "rounddown")

			assert.are.equal(expected_quantity, tostring(res))
    end)
  end)

	describe("formatNativeAsInternal()", function ()
  	local collateral_denomination = 12

    before_each(function ()
  		_G.CollateralDenomination = collateral_denomination
    end)

    it("should early return zero for zero input", function ()
      local res = precision.formatNativeAsInternal("0")

      assert.are.equal("0", res)
    end)

    it("should early return the same amount if the precision difference is 0", function ()
      local high_denomination = 22
			_G.CollateralDenomination = high_denomination

			local quantity = "242356236"

			local res = precision.formatNativeAsInternal(quantity)

			assert.are.equal(quantity, res)
    end)

    it("should return the formatted quantity using the precision difference", function ()
      local quantity = "6432569"
      local expected_quantity = tostring(bint(quantity) * bint.ipow(10, 18 - collateral_denomination))

      local res = precision.formatNativeAsInternal(quantity)

      assert.are.equal(expected_quantity, res)
    end)
  end)

	describe("formatInternalAsNative()", function ()
  	local collateral_denomination = 12

    before_each(function ()
  		_G.CollateralDenomination = collateral_denomination
    end)

    it("should early return zero for zero input", function ()
      local res = precision.formatInternalAsNative("0")

      assert.are.equal("0", res)
    end)

    it("should early return the same amount if the precision difference is 0", function ()
      local high_denomination = 22
			_G.CollateralDenomination = high_denomination

			local quantity = "93578526"

			local res = precision.formatInternalAsNative(quantity)

			assert.are.equal(quantity, res)
    end)

    it("should return the correct rounded up quantity", function ()
      local expected_quantity = "823756792"
			local internal_quantity = tostring((bint(expected_quantity) - bint.one()) * bint.ipow(10, 18 - collateral_denomination) + bint.one())

			local res = precision.formatInternalAsNative(internal_quantity, "roundup")

			assert.are.equal(expected_quantity, res)
		end)

    it("should return the correct rounded down quantity", function ()
      local expected_quantity = "382975626"
			local internal_quantity = tostring(bint(expected_quantity) * bint.ipow(10, 18 - collateral_denomination) + bint(string.rep("9", 18 - collateral_denomination)))

			local res = precision.formatInternalAsNative(internal_quantity, "rounddown")

			assert.are.equal(expected_quantity, res)
    end)
  end)
end)
