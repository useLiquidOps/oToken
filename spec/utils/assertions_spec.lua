local assertions = require "utils.assertions"

describe("Assertion tests", function ()
  describe("isAddress()", function ()
    it("should fail for non-string addresses", function ()
      local table_res = assertions.isAddress({})
      local num_res = assertions.isAddress(1)
      local bool_res = assertions.isAddress(true)
      local nil_res = assertions.isAddress(nil)

      assert.is_false(table_res)
      assert.is_false(num_res)
      assert.is_false(bool_res)
      assert.is_false(nil_res)
    end)

    it("should fail for an invalid length", function ()
      local short_res = assertions.isAddress("a")
      local long_res = assertions.isAddress(string.rep("b", 50))
      local empty_res = assertions.isAddress("")

      assert.is_false(short_res)
      assert.is_false(long_res)
      assert.is_false(empty_res)
    end)

    it("should fail for invalid characters", function ()
      local unicode_res = assertions.isAddress(string.rep("é", 43))
      local invalid_char_res = assertions.isAddress(string.rep("a", 42) .. ".")

      assert.is_false(unicode_res)
      assert.is_false(invalid_char_res)
    end)

    it("should succeed for a valid address", function ()
      local lowercase_res = assertions.isAddress(string.rep("a", 43))
      local uppercase_res = assertions.isAddress(string.rep("A", 43))
      local standard_res = assertions.isAddress(
        "xZvCPN31XCLPkBo9FU_B7vAK0VC6-eY52-CS-6Iho8U"
      )

      assert.is_true(lowercase_res)
      assert.is_true(uppercase_res)
      assert.is_true(standard_res)
    end)
  end)

  describe("isValidNumber()", function ()
    it("should fail for a non-number input", function ()
      local table_res = assertions.isValidNumber({})
      local str_res = assertions.isValidNumber("2324")
      local bool_res = assertions.isValidNumber(true)
      local nil_res = assertions.isValidNumber(nil)

      assert.is_false(table_res)
      assert.is_false(str_res)
      assert.is_false(bool_res)
      assert.is_false(nil_res)
    end)

    it("should fail for nan", function ()
      local nan_res = assertions.isValidNumber(0 / 0)

      assert.is_false(nan_res)
    end)

    it("should fail for infinity", function ()
      local plus_inf_res = assertions.isValidNumber(1 / 0)
      local minus_inf_res = assertions.isValidNumber(-1 / 0)
      local plus_huge_res = assertions.isValidNumber(math.huge)
      local minus_huge_res = assertions.isValidNumber(-math.huge)

      assert.is_false(plus_inf_res)
      assert.is_false(minus_inf_res)
      assert.is_false(plus_huge_res)
      assert.is_false(minus_huge_res)
    end)

    it("should succeed for a valid number", function ()
      local plus_res = assertions.isValidNumber(24)
      local minus_res = assertions.isValidNumber(-12)
      local zero_res = assertions.isValidNumber(0)
      local fractional_res = assertions.isValidNumber(math.exp(1))

      assert.is_true(plus_res)
      assert.is_true(minus_res)
      assert.is_true(zero_res)
      assert.is_true(fractional_res)
    end)
  end)

  describe("isValidInteger()", function ()
    it("should fail for an invalid number", function ()
      local inf_res = assertions.isValidInteger(math.huge)

      assert.is_false(inf_res)
    end)

    it("should fail for a fractional number", function ()
      local frac_res = assertions.isValidInteger(1.25)

      assert.is_false(frac_res)
    end)

    it("should succeed for a whole number/integer", function ()
      local integer_res = assertions.isValidInteger(2356)
      local whole_res = assertions.isValidNumber(24.0)

      assert.is_true(integer_res)
      assert.is_true(whole_res)
    end)
  end)

  describe("isBintRaw()", function()
    it("should fail if the number is not convertible to a biginteger", function ()
      local table_res = assertions.isBintRaw({})
      local bool_res = assertions.isBintRaw(false)

      assert.is_false(table_res)
      assert.is_false(bool_res)
    end)

    it("should fail if the number is not a valid integer", function ()
      local frac_res = assertions.isBintRaw(1.25)
      local frac_res_str = assertions.isBintRaw("1.25")
      local inf_res = assertions.isBintRaw()

      assert.is_false(frac_res)
      assert.is_false(frac_res_str)
      assert.is_false(inf_res)
    end)

    it("should succeed if the number is a valid bigint", function ()
      local int_res = assertions.isBintRaw(1256)
      local string_res = assertions.isBintRaw("56832")

      assert.is_true(int_res)
      assert.is_true(string_res)
    end)
  end)

  describe("isTokenQuantity()", function ()
    it("should fail for not numbers", function ()
      local table_res = assertions.isTokenQuantity({})
      local bool_res = assertions.isTokenQuantity(false)

      assert.is_false(table_res)
      assert.is_false(bool_res)
    end)

    it("should fail for zero", function ()
      local zero_res = assertions.isTokenQuantity(0)
      local zero_res_str = assertions.isTokenQuantity("0")

      assert.is_false(zero_res)
      assert.is_false(zero_res_str)
    end)

    it("should fail for negative numbers", function ()
      local num_res = assertions.isTokenQuantity(-215)
      local string_res = assertions.isTokenQuantity("-9285")

      assert.is_false(num_res)
      assert.is_false(string_res)
    end)

    it("should fail for invalid bigintegers", function ()
      local frac_res = assertions.isTokenQuantity("1.256")
      local inf_res = assertions.isTokenQuantity(math.huge)

      assert.is_false(frac_res)
      assert.is_false(inf_res)
    end)

    it("should succeed for a valid token quantity", function ()
      local num_res = assertions.isTokenQuantity(15)
      local str_res = assertions.isTokenQuantity("235612")

      assert.is_true(num_res)
      assert.is_true(str_res)
    end)
  end)

  describe("isCollateralizedWith()", function()
    it("should fail for a borrow balance that is too high", function ()
      local more_res = assertions.isCollateralizedWith(
        0,
        { borrowBalance = 2, capacity = 1 }
      )
      local equal_res = assertions.isCollateralizedWith(
        0,
        { borrowBalance = 1, capacity = 1 }
      )

      assert.is_false(more_res)
      assert.is_false(equal_res)
    end)

    it("should fail for an added debt that is too high", function ()
      local res = assertions.isCollateralizedWith(
        2,
        { borrowBalance = 3, capacity = 4 }
      )

      assert.is_false(res)
    end)

    it("should succeed for the correct added dept", function ()
      local less_res = assertions.isCollateralizedWith(
        1,
        { borrowBalance = 2, capacity = 4 }
      )
      local equal_res = assertions.isCollateralizedWith(
        2,
        { borrowBalance = 2, capacity = 4 }
      )

      assert.is_true(less_res)
      assert.is_true(equal_res)
    end)
  end)

  describe("isCollateralizedWithout()", function ()
    it("should fail for a removed capacity that is too high", function ()
      local more_res = assertions.isCollateralizedWithout(
        2,
        { capacity = 1 }
      )
      local equal_res = assertions.isCollateralizedWithout(
        1,
        { capacity = 1 }
      )

      assert.is_false(more_res)
      assert.is_false(equal_res)
    end)

    it("should fail for a borrow balance that is too high", function ()
      local res = assertions.isCollateralizedWithout(
        1,
        { capacity = 2, borrowBalance = 2 }
      )

      assert.is_false(res)
    end)

    it("should succeed for a correct removed capacity", function ()
      local equal_res = assertions.isCollateralizedWithout(
        1,
        { capacity = 3, borrowBalance = 2 }
      )
      local more_res = assertions.isCollateralizedWithout(
        1,
        { capacity = 4, borrowBalance = 2 }
      )

      assert.is_true(equal_res)
      assert.is_true(more_res)
    end)
  end)

  describe("isPercentage()", function ()
    it("should fail for an invalid number", function ()
      local nil_res = assertions.isPercentage(nil)
      local str_res = assertions.isPercentage("25")
      local table_res = assertions.isPercentage({})
      local bool_res = assertions.isPercentage(true)

      assert.is_false(nil_res)
      assert.is_false(str_res)
      assert.is_false(table_res)
      assert.is_false(bool_res)
    end)

    it("should fail for a non-whole/inf number", function ()
      local frac_res = assertions.isPercentage(1.15)
      local inf_res = assertions.isPercentage(math.huge)

      assert.is_false(frac_res)
      assert.is_false(inf_res)
    end)

    it("should fail for a number outside of [0, 100]", function ()
      local less_res = assertions.isPercentage(-1)
      local more_res = assertions.isPercentage(102)

      assert.is_false(less_res)
      assert.is_false(more_res)
    end)

    it("should succeed for a valid percentage", function ()
      local res = assertions.isPercentage(83)

      assert.is_true(res)
    end)
  end)

  describe("isFriend()", function ()
    local friend_otoken = "some_otoken_id"
    before_each(function ()
      _G.Friends = {
        { id = "some_id", ticker = "AR", oToken = friend_otoken, denomination = 12 }
      }
    end)

    it("should fail for an oToken, that is not in the friends list", function ()
      local res = assertions.isFriend("some_other_otoken_id")

      assert.is_false(res)
    end)

    it("should succeed for a friend oToken id", function ()
      local res = assertions.isFriend(friend_otoken)

      assert.is_true(res)
    end)
  end)
end)
