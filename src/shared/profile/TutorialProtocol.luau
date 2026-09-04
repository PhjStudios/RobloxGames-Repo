--!strict

local PayloadValidation = require(script.Parent.Parent.network.PayloadValidation)
local Result = require(script.Parent.Parent.util.Result)
local Validation = require(script.Parent.Parent.util.Validation)

export type Step = number

export type View = {
	version: number,
	firstJoin: boolean,
	tutorialCompleted: boolean,
	tutorialStep: Step,
	attempt: number,
	skipped: boolean,
	trackedMatchId: string?,
}

export type ActionIntent = {
	transactionId: string,
	expectedRevision: number,
}

export type MutationReceipt = {
	transactionId: string,
	changed: boolean,
	revision: number,
	tutorial: View,
}

local VERSION = 1
local COMPLETE_STEP = 9
local POSITIVE_SAFE_INTEGER = PayloadValidation.integer(1, Validation.MAX_SAFE_INTEGER)
local VIEW = PayloadValidation.record({
	version = PayloadValidation.integer(VERSION, VERSION),
	firstJoin = PayloadValidation.boolean(),
	tutorialCompleted = PayloadValidation.boolean(),
	tutorialStep = PayloadValidation.integer(0, COMPLETE_STEP),
	attempt = PayloadValidation.integer(1, 1_000_000),
	skipped = PayloadValidation.boolean(),
	trackedMatchId = PayloadValidation.optional(PayloadValidation.id("match")),
})
local ActionIntentSchema = PayloadValidation.schema(PayloadValidation.record({
	transactionId = PayloadValidation.id("transaction"),
	expectedRevision = POSITIVE_SAFE_INTEGER,
}))
local ViewSchema = PayloadValidation.schema(VIEW)
local MutationReceiptSchema = PayloadValidation.schema(PayloadValidation.record({
	transactionId = PayloadValidation.id("transaction"),
	changed = PayloadValidation.boolean(),
	revision = POSITIVE_SAFE_INTEGER,
	tutorial = VIEW,
}))

local TutorialProtocol = {
	VERSION = VERSION,
	COMPLETE_STEP = COMPLETE_STEP,
	ActionIntentSchema = ActionIntentSchema,
	ViewSchema = ViewSchema,
	MutationReceiptSchema = MutationReceiptSchema,
}

local function issue(path: { Validation.PathSegment }, message: string)
	return Result.err(Validation.issue("INVALID_REFERENCE", path, message))
end

function TutorialProtocol.validateView(value: unknown): Result.Result<View, Validation.Issue>
	local parsed = ViewSchema:validate(value)
	if not parsed.ok then
		return Result.err(parsed.error)
	end
	local view = parsed.value :: View
	if view.firstJoin ~= (view.tutorialStep == 0) then
		return issue({ "payload", "firstJoin" }, "Only uninitialized tutorial state may be first join")
	end
	if view.tutorialCompleted ~= (view.tutorialStep == COMPLETE_STEP) then
		return issue({ "payload", "tutorialCompleted" }, "Only the terminal tutorial state may be complete")
	end
	if view.skipped and view.tutorialStep ~= COMPLETE_STEP then
		return issue({ "payload", "skipped" }, "Skipped tutorial state must be terminal")
	end
	local requiresMatch = view.tutorialStep >= 5 and view.tutorialStep <= 8
	if requiresMatch ~= (view.trackedMatchId ~= nil) then
		return issue({ "payload", "trackedMatchId" }, "Tracked match must exist exactly during Match tutorial states")
	end
	return Result.ok(view)
end

function TutorialProtocol.validateMutationReceipt(value: unknown): Result.Result<MutationReceipt, Validation.Issue>
	local parsed = MutationReceiptSchema:validate(value)
	if not parsed.ok then
		return Result.err(parsed.error)
	end
	local receipt = parsed.value :: MutationReceipt
	local tutorial = TutorialProtocol.validateView(receipt.tutorial)
	if not tutorial.ok then
		return Result.err(tutorial.error)
	end
	return Result.ok(receipt)
end

return table.freeze(TutorialProtocol)
