-- TimeObject.lua
-- 「先送り/巻き戻し」で移動するオブジェクト。
-- hitBoxSize × Transform Scale を、矢が当たる矩形サイズとして Player へ通知する。

properties = {
  { name = "axis",         type = "vec3",  default = {0, 1, 0},              label = "動く方向" },
  { name = "amplitude",    type = "float", default = 3.0, min = 0, max = 20, label = "先送りで動く量" },
  { name = "minOffset",    type = "float", default = 0.0,                    label = "offset下限" },

  -- 1.0 = 元オブジェクトが 1×1 の場合にちょうどその大きさ。
  -- 例: hitBoxSize={1,1,1}、Transform Scale={3,2,1} なら判定は横3・縦2。
  { name = "hitBoxSize",   type = "vec3",  default = {1, 1, 1},              label = "矢の判定サイズ(Scale前)" },

  { name = "deadlyRadius", type = "float", default = 0.9, min = 0, max = 5, label = "接触判定半径(0で無効)" },
  { name = "blockRatio",   type = "float", default = 0.5, min = 0, max = 1, label = "この割合未満のoffsetで塞ぐ判定" },
}

local function getWorldHitBoxSize(self)
  local width = math.abs(self.hitBoxSize.x or 1.0)
  local height = math.abs(self.hitBoxSize.y or 1.0)

  -- Transform Scale が取得できる場合は、描画と同じ拡大・縮小を判定にも反映する。
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

  -- Player がエンティティ名ではなくタグで時間操作対象を判定できるようにする。
  -- TimeObject タグの対象だけが time_skip を受けて移動する。
  events:emit("arrow_target_bounds", {
    target = self.name,
    tag = "TimeObject",
    x = p.x,
    y = p.y,
    width = width,
    height = height,
  })
end

function OnStart(self)
  local p = self.transform.position
  self.bx, self.by, self.bz = p.x, p.y, p.z
  self.offset = 0
  self.maxOffset = self.amplitude

  events:on("time_skip", function(data)
    if data.target ~= self.name then return end

    self.offset = self.offset + data.dir * data.amount
    if self.offset > self.maxOffset then self.offset = self.maxOffset end
    if self.offset < self.minOffset then self.offset = self.minOffset end
  end)

  sendArrowBounds(self)
end

function OnUpdate(self, dt)
  self.transform.position = Vec3.new(
    self.bx + self.axis.x * self.offset,
    self.by + self.axis.y * self.offset,
    self.bz + self.axis.z * self.offset)

  -- 動いた後の位置とサイズを毎フレーム通知する。
  sendArrowBounds(self)

  if self.deadlyRadius <= 0 then return end

  local blocking = math.abs(self.offset) < (self.amplitude * self.blockRatio)
  if not blocking then return end

  local pl = scene:findEntity("Player")
  if not (pl and pl:isValid()) then return end

  local me, pp = self.transform.position, pl.transform.position
  local dx, dy = me.x - pp.x, me.y - pp.y
  if dx * dx + dy * dy < self.deadlyRadius * self.deadlyRadius then
    events:emit("player_died", {})
  end
end
