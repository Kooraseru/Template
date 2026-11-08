local Renderer = {}

function Renderer.drawFrame(): ()
end

function Renderer:_resetFrame(): ()
end

Renderer.drawPreview = function(): ()
end

Renderer["drawCursor"] = function(): ()
end

return Renderer
