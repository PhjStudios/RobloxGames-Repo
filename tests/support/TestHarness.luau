--!strict

export type AssertionFailure = {
	code: string,
	assertion: string,
}

export type Assertions = {
	equal: (actual: unknown, expected: unknown) -> (),
	notEqual: (actual: unknown, unexpected: unknown) -> (),
	isTrue: (value: unknown) -> (),
	isFalse: (value: unknown) -> (),
	isNil: (value: unknown) -> (),
	isNotNil: (value: unknown) -> (),
	contains: (value: unknown, fragment: unknown) -> (),
}

export type TestCase = {
	name: string,
	run: (assertions: Assertions) -> (),
}

export type Suite = {
	name: string,
	cases: { TestCase },
}

local TestHarness = {}

local FAILURE_REGISTRY = setmetatable({}, { __mode = "k" }) :: { [any]: boolean }

local function fail(assertion: string, code: string): never
	local failure = table.freeze({
		assertion = assertion,
		code = code,
	})
	FAILURE_REGISTRY[failure] = true
	error(failure, 0)
end

local Assertions: Assertions = table.freeze({
	equal = function(actual: unknown, expected: unknown)
		if actual ~= expected then
			fail("equal", "ASSERT_EQUAL_FAILED")
		end
	end,
	notEqual = function(actual: unknown, unexpected: unknown)
		if actual == unexpected then
			fail("notEqual", "ASSERT_NOT_EQUAL_FAILED")
		end
	end,
	isTrue = function(value: unknown)
		if value ~= true then
			fail("isTrue", "ASSERT_TRUE_FAILED")
		end
	end,
	isFalse = function(value: unknown)
		if value ~= false then
			fail("isFalse", "ASSERT_FALSE_FAILED")
		end
	end,
	isNil = function(value: unknown)
		if value ~= nil then
			fail("isNil", "ASSERT_NIL_FAILED")
		end
	end,
	isNotNil = function(value: unknown)
		if value == nil then
			fail("isNotNil", "ASSERT_NOT_NIL_FAILED")
		end
	end,
	contains = function(value: unknown, fragment: unknown)
		if type(value) ~= "string" or type(fragment) ~= "string" or string.find(value, fragment, 1, true) == nil then
			fail("contains", "ASSERT_CONTAINS_FAILED")
		end
	end,
})

function TestHarness.case(name: string, callback: (assertions: Assertions) -> ()): TestCase
	return table.freeze({
		name = name,
		run = callback,
	})
end

function TestHarness.suite(name: string, cases: { TestCase }): Suite
	return table.freeze({
		name = name,
		cases = table.freeze(cases),
	})
end

function TestHarness.getAssertions(): Assertions
	return Assertions
end

function TestHarness.getFailure(value: unknown): AssertionFailure?
	if type(value) ~= "table" or FAILURE_REGISTRY[value] ~= true then
		return nil
	end

	return value :: AssertionFailure
end

return table.freeze(TestHarness)
