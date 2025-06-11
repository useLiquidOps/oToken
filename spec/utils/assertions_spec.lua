local assertions = require "utils.assertions"

describe("Assertion tests", function ()
  describe("Address assertion", function ()
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

  describe("Valid number assertion", function ()
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
end)
