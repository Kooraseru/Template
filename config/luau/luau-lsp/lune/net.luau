--!strict

-- Analyzer-only declaration for the Lune HTTP request operation.
local Network = {} :: {
	request: (url: string) -> {
		ok: boolean,
		statusCode: number,
		statusMessage: string,
		headers: { [string]: string },
		body: string,
	},
}

return Network
