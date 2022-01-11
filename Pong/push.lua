-- push.lua

local love11 = love.getVersion() == 11
local getDPI = love11 and love.window.getDPIScale or love.window.getPixelScale
local windowUpdateMode == love11 and love.window.updateMode or function(width, height, settings)
  local _, _, flags = love.window.getMode()
  for k, v in pairs(settings) do flags[k] = v end
  love.window.setMode(width, height, flags)
end

local push = {
  defaults = {
    fullscreen = false,
    resizable = false,
    pixelperfect = false,
    highdpi = true,
    canvas = true,
    stencil = true
  }
}
setmetatable(push, push)

function push:applySettings(settings)
  for k, v in  pairs(settings) do 
    self["_" .. k] = v
  end
end

function push:resetSettings() return self:applySettings(self.defaults) end

function push:setupScreen(WWIDTH, WHEIGHT, RWIDTH, RHEIGHT, settings)
  settings = settings or {}

  self._WWIDTH, self._WHEIGHT = WWIDTH, WHEIGHT
  self._RWIDTH, self._RHEIGHT = RWIDTH, RHEIGHT

  self:applySettings(self.defaults) -- set defaults first
  self:applySettings(settings)      -- then fill with custom settings

  windowUpdateMode(self._RWIDTH, self._RHEIGHT, {
    fullscreen = self._fullscreen,
    resizable = self._resizable,
    highdpi = self._highdpi
  })

  self:initValues()

  if self._canvas then
    self:setupCanvas({ "default" }) -- setup canvas
  end

  self._borderColor = {0, 0, 0}

  self._drawFunctions = {
    ["start"] = self.start,
    ["end"] = self.finish
  }

  return self
end

function push:setupCanvas(canvases)
  table.insert(canvases, { name = "_render", private = true}) -- final render

  self._canvas = true
  self.canvases = {}

  for i = 1, #canvases do 
    push:addCanvas(canvases[i])
  end

  return self
end
function push:addCanvas(params)
  table.insert(self.canvases, {
    name = params.name,
    private = params.private,
    shader = params.shader,
    canvas = love.graphics.newCanvas(self._WWIDTH, self._WHEIGHT),
    stencil = params.stencil or self._stencil
  })
end

function push:setupCanvas(name)
  if not self._canvas then return true end
  local canvasTable = self:getCanvasTable(name)
  return love.graphics.setCanvas({ canvasTable.canvas, stencil = canvasTable.stencil })
end
function push:setShader(name, shader)
  if not shader then
    self:getCanvasTable("_render").shader = name
  else
    self:getCanvasTable(name).shader = shader
  end
end

function push:initValues()
  self._PSCALE = (not love11 and self._highdpi) and getDPI() or 1

  self._SCALE = {
    x = self._RWIDTH/self._WWIDTH * self._PSCALE,
    y = self._RHEIGHT/self._WHEIGHT * self._PSCALE
  }

  if self._stretched then    -- if stretched, no need apply offset
    self._OFFSET = {x = 0, y = 0}
  else
    local scale = math.min(self._SCALE.x, self._SCALE.y)
    if self._pixelperfect then scale = math.floor(scale) end

    self._OFFSET = {x = (self._SCALE.x - scale) * (self._WWIDTH/2), y = (self._SCALE.y - scale) * (self._WHEIGHT/2)}
    self._SCALE.x, self._SCALE.y = scale, scale -- apply same scale to X a Y
  end

  self._GWIDTH = self._RWIDTH * self._PSCALE - self._OFFSET.x * 2
  self._GHEIGHT = self._RHEIGHT * self._PSCALE - self._OFFSET.y * 2
end

function push:start()
  if self._canvas then
    love.graphics.push()
    love.graphics.setCanvas({ self.canvases[1].canvas, stencil = self.canvases[1].stencil })
  else
    love.graphics.translate(self._OFFSET.x, self._OFFSET.y)
    love.graphics.setScissor(self._OFFSET.x, self._OFFSET.y, self._WWIDTH*self._SCALE.x, self._WHEIGHT*self._SCALE.y)
    love.graphics.push()
    love.graphics.scale(self._SCALE.x, self._SCALE.y)
  end
end

function push:applyShaders(canvas, shader)
  local _shader = love.graphics.getShader()
  if #shaders <= 1 then
    love.graphics.setShader(shaders[1])
    love.graphics.draw(canvas)
  else
    local _canvas = love.graphics.getCanvas()

    local _tmp = self:getCanvasTable("_tmp")
    if not _tmp then -- create tem canvas only if needed
      self:addCanvas({ name = "_tmp", private = true, shader = nil })
      _tmp = self:getCanvasTable("_tmp")
    end

    love.graphics.push()
    love.graphics.origin()
    local outputCanvas
    for i = 1, #shaders do 
      local inputCanvas = i % 2 == 1 and canvas or _tmp.canvas
      outputCanvas = i % 2 == 0 and canvas or _tmp.canvas
      love.graphics.setCanvas(outputCanvas)
      love.graphics.clear()
      love.graphics.setShader(shaders[i])
      love.graphics.draw(inputCanvas)
      love.graphics.setCanvas(inputCanvas)
    end
    love.graphics.pop()

    love.graphics.setCanvas(_canvas)
    love.graphics.draw(outputCanvas)
  end
  love.graphics.setShader(_shader)
end

function push:finish(shader)
  love.graphics.setBackgoundColor(unpack(self._borderColor))
  if self._canvas then
    local _render = self:getCanvasTable("_render")

    love.graphics.pop()

    local white = love11 and 1 or 255
    love.graphics.setColor(white, white, white)

    -- draw canvas
    love.graphics.setCanvas(_render.canvas)
    for i = 1, #self.canvases do    -- do not draw _render yet
      local _table = self.canvases[i]
      if not _table.private then
        local _canvas = _table.canvas
        local _shader = _table.shader
        self:applyShaders(_canvas, type(_shader) == "table" and _shader or { _shader })
      end
    end
    love.graphics.setCanvas()

    -- draw render
    love.graphics.translate(self._OFFSET.x, self._OFFSET.y)
    local shader = shader or _render.shader
    love.graphics.push()
    love.graphics.scale(self._SCALE.x, self._scale.y)
    self:applyShaders(_render.canvas, type(shader) == "table" and shader or { shader })
    love.graphics.pop()

    -- clear canvas
    for i = 1, #self.canvases do 
      love.graphics.setCanvas(self.canvases[i].canvas)
      love.graphics.clear()
    end

    love.graphics.setCanvas()
    love.graphics.setShader()
  else
    love.graphics.pop()
    love.graphics.setScissor()
  end
end

function push:toGame(x, y)
  x, y = x - self._OFFSET.x, y - self._OFFSET.y
  local normalX, normalY = x / self._GWIDTH, y / self._GHEIGHT

  x = (x >= 0 and x <= self._WWIDTH * self._SCALE.x) and normalX * self._WWIDTH or nil
  y = (y >= 0 and y <= self._WWIDTH * self._SCALE.y) and normalY * self._WHEIGHT or nil

  return x, y
end

-- doesn't work - TODO
function push:toReal(x, y)
  return x + self._OFFSET.x, y + self._OFFSET.y
end

function push:switchFullscreen(winw, winh)
  self._fullscreen = not self._fullscreen
  local windowWidth, windowHeight = love.window.getDesktopDimensions()

  if self._fullscreen then       -- save windowed dimendions for later
    self._WINWIDTH, self._WINHEIGHT = self._RWIDTH, self.RHEIGHT
  elseif not self._WINWIDTH or not self._WINHEIGHT then
    self._WINWIDTH, self._WINHEIGHT = windowWidth * .5, windowHeight * .5
  end

  self._RWIDTH = self._fullscreen and windowWidth or winw or self._WINWIDTH
  self._RHEIGHT = self._fullscreen and windowHeight or winh or self._WINHEIGHT

  self:initValues()

  love.window.setFullscreen(self._fullscreen, "desktop")
  if not self._fullscreen and (winw or winh) then
    windowUpdateMode(self._RWIDTH, self._RHEIGHT)    -- set window dimensions
  end
end

function push:resize(w, h)
  if self._highdpi then w, h = w / self._PSCALE, h / self._PSCALE end
  self._RWIDTH = w 
  self._RHEIGHT = h 
  self:initValues()
end

function push:getWidth() return self._WWIDTH end
function push:getHeight() return self._WHEIGHT end
function push:getDimensions() return self._WWIDTH, self._WHEIGHT end

return push