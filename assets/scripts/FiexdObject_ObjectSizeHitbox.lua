-- FiexdObject.lua
-- 動かない矢の命中対象。
-- hitBoxSize × Transform Scale が、矢の当たり判定の横幅・縦幅になる。

properties = {
  -- 1.0 = 元オブジェクトが 1×1 の場合にちょうどその大きさ。
  -- 例: hitBoxSize={1,1,1}、Transform Scale={4,1.5,1} なら判定は横4・縦1.5。
  { name = "hitBoxSize", type = "vec3", default = {1, 1, 1}, label = "矢の判定サイズ(Scale前)" },
  { name = "notifyOnHit", type = "bool", default = true, label = "命中イベントを送る" },
}

local function getWorldHitBoxSize(self)
  local width = math.abs(self.hitBoxSize.x or 1.0)
  local height = math.abs(self.hitBoxSize.y or 1.0)

  local ok, scale = pcall(function()
    return self.transform.scale
  end)

  if ok and scale then
    width = width * math.abs(scale.x or 1.0)
    height = height * math.abs(scale.y or 1.0)
  end

  return math.max(width, 0.01), math.max(height, 0.01)
end

local function sendArrowBounds(self)
  local p = self.transform.position
  local width, height = getWorldHitBoxSize(self)

  -- Player がエンティティ名ではなくタグで固定対象を判定できるようにする。
  -- FiexdObject タグの対象は矢が刺さっても時間操作では動かさない。
  events:emit("arrow_target_bounds", {
    target = self.name,
    tag = "FiexdObject",
    x = p.x,
    y = p.y,
    width = width,
    height = height,
  })
end

function OnStart(self)
  local p = self.transform.position
  self.baseX, self.baseY, self.baseZ = p.x, p.y, p.z
  self.wasHit = false

  events:on("arrow_hit", function(data)
    if data.target ~= self.name then return end

    self.wasHit = true

    if self.notifyOnHit then
      events:emit("fixed_object_hit", {
        target = self.name,
        dir = data.dir,
        amount = data.amount,
      })
    end
  end)

  sendArrowBounds(self)
end

function OnUpdate(self, dt)
  -- 固定オブジェクトなので開始位置を維持する。
  self.transform.position = Vec3.new(self.baseX, self.baseY, self.baseZ)

  -- Player の矢判定用に、現在の位置とサイズを通知する。
  sendArrowBounds(self)
end
