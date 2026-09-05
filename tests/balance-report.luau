--!strict

local fs = require("@lune/fs")
local process = require("@lune/process")

-- Reuse the repository's Roblox-aware loader and production-runtime simulation.
local executed = process.exec("lune", { "run", "tests/run.luau", "--spec", "ContentBalanceReport" })
if not executed.ok then
	print(executed.stdout)
	print(executed.stderr)
	process.exit(1)
end
local report = string.match(executed.stdout, "ATD_BALANCE_REPORT_BEGIN\n(.-)ATD_BALANCE_REPORT_END")
assert(report ~= nil, "balance report export marker missing")
if not fs.isDir("build") then
	fs.writeDir("build")
end
fs.writeFile("build/content-balance-report.md", report)
print("Read-only deterministic report: build/content-balance-report.md")
