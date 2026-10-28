-- ci/preflight/contracts.luau
--!strict

local BootstrapContract = require("@ci/bootstrap/contract")

local Contracts = {}

export type Diagnostic = {
	path: string,
	line: number,
	column: number,
	endColumn: number,
	severity: "error" | "warning" | "info",
	message: string,
	source: string?,
	endLine: number?,
}

export type Task = BootstrapContract.Task

export type ProviderPackage = {
	identity: string,
	provider: string,
	directory: string,
	configPath: string,
	enabled: boolean,
	options: { [string]: unknown },
}

export type Context = {
	event: string,
	planAvailable: boolean,
	tasks: { BootstrapContract.Task },
}

export type ProviderResult = { diagnostics: { Diagnostic } }

export type ProviderInstance = {
	Analyze: (self: ProviderInstance, context: Context) -> ProviderResult,
}

export type ProviderClass = {
	new: (configuration: ProviderPackage) -> ProviderInstance,
}

return Contracts
