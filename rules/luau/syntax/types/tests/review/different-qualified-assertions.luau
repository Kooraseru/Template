local Raw = require("../Raw")
local Model = require("../Model")
local function read(value: Raw.Record): Model.Record
	return (value :: Raw.Record) :: Model.Record
end
return read
