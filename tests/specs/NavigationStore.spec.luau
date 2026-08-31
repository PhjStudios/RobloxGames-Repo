--!strict

local TestHarness = require(script.Parent.Parent.Support.TestHarness)
local NavigationStore = require(script.Parent.Parent.ProductionClientCommonUi.NavigationStore)

local function expectSuccess(value: any): any
	if not value.ok then
		error(`unexpected navigation failure: {value.error.code}`, 0)
	end
	return value.value
end

return TestHarness.suite("bounded Lobby navigation store", {
	TestHarness.case("owns one primary screen and detached per-screen memory", function(assertions)
		local store = expectSuccess(NavigationStore.new())
		local initial = expectSuccess(store:getSnapshot())
		assertions.equal(initial.activeScreen, "Home")
		assertions.equal(initial.revision, 0)
		assertions.equal(#initial.modals, 0)
		assertions.equal(initial.memory.Inventory.scrollOffset, 0)
		assertions.isTrue(table.isfrozen(initial))
		assertions.isTrue(table.isfrozen(initial.memory.Inventory))

		assertions.isTrue(expectSuccess(store:remember("Inventory", "tower:dart-ant", 180)))
		assertions.isTrue(expectSuccess(store:setPrimary("Inventory")))
		local changed = expectSuccess(store:getSnapshot())
		assertions.equal(changed.activeScreen, "Inventory")
		assertions.equal(changed.memory.Inventory.selectionKey, "tower:dart-ant")
		assertions.equal(changed.memory.Inventory.scrollOffset, 180)
		assertions.equal(changed.revision, 2)
		assertions.isFalse(expectSuccess(store:setPrimary("Inventory")))
		store:cleanup()
	end),

	TestHarness.case("bounds unique modals and blocks click-through navigation", function(assertions)
		local store = expectSuccess(NavigationStore.new("Chests"))
		for index = 1, NavigationStore.MAX_MODAL_DEPTH do
			assertions.isTrue(expectSuccess(store:pushModal(`modal:{index}`, `focus:{index}`)))
		end
		assertions.equal(#expectSuccess(store:getSnapshot()).modals, NavigationStore.MAX_MODAL_DEPTH)
		assertions.equal(store:pushModal("modal:overflow").error.code, "MODAL_STACK_FULL")
		assertions.equal(store:pushModal("modal:1").error.code, "DUPLICATE_MODAL")
		assertions.equal(store:setPrimary("Settings").error.code, "MODAL_ACTIVE")
		store:cleanup()
	end),

	TestHarness.case("Back closes only the top modal then returns the primary screen Home", function(assertions)
		local store = expectSuccess(NavigationStore.new("Inventory"))
		store:pushModal("detail", "tower:rapid-ant")
		store:pushModal("confirm", "equip")

		local first = expectSuccess(store:back())
		assertions.equal(first.kind, "ModalClosed")
		assertions.equal(first.modalId, "confirm")
		assertions.equal(first.restoreFocusKey, "equip")
		assertions.equal(#expectSuccess(store:getSnapshot()).modals, 1)

		local second = expectSuccess(store:back())
		assertions.equal(second.modalId, "detail")
		assertions.equal(expectSuccess(store:getSnapshot()).activeScreen, "Inventory")
		assertions.equal(expectSuccess(store:back()).kind, "ScreenChanged")
		assertions.equal(expectSuccess(store:getSnapshot()).activeScreen, "Home")
		assertions.equal(expectSuccess(store:back()).kind, "Noop")
		store:cleanup()
	end),

	TestHarness.case("rejects malformed state and becomes inert after idempotent cleanup", function(assertions)
		assertions.equal(NavigationStore.new("Admin").error.code, "INVALID_ARGUMENT")
		local store = expectSuccess(NavigationStore.new())
		assertions.equal(store:remember("Inventory", "bad key", 0).error.code, "INVALID_ARGUMENT")
		assertions.equal(store:remember("Inventory", nil, -1).error.code, "INVALID_ARGUMENT")
		assertions.equal(store:pushModal("bad modal").error.code, "INVALID_ARGUMENT")
		assertions.isTrue(expectSuccess(store:cleanup()))
		assertions.isTrue(expectSuccess(store:cleanup()))
		assertions.equal(store:getSnapshot().error.code, "CLEANED_UP")
		assertions.equal(store:back().error.code, "CLEANED_UP")
	end),
})
