--!strict

-- Analyzer-only declaration for the Lune date/time surface consumed by CI.
export type DateTime = {
    unixTimestampMillis: number,
    toIsoDate: (self: DateTime) -> string,
}

local Datetime = {} :: {
    now: () -> DateTime,
    fromRfc3339: (text: string) -> DateTime,
    fromRfc2822: (text: string) -> DateTime,
    fromUnixTimestamp: (seconds: number) -> DateTime,
}

return Datetime
