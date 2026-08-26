--!strict

-- tests/run.luau replaces this exact test-only ModuleScript with a restricted
-- host adapter. Direct execution fails closed so no unsupported simulation can
-- be mistaken for Roblox engine behavior.
error("[ATD_TEST_ADAPTER][code=HOST_ADAPTER_REQUIRED]", 0)
