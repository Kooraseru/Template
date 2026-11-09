local Model = require("../Model")
local function read(value: Model.Record): Model.Record
	return (value :: Model.Record) :: Model.Record
end
return read
