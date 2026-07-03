-- TimeObject.lua -- 「先送り/巻き戻し」で動くオブジェクトに貼る。
-- 矢が刺さると Player.lua が events:emit("time_skip", {target=name, dir, amount}) を発行し、
-- 自分の名前と一致すれば axis方向へ offset をずらす(スナップ、テレポート)。
-- offset が小さい(=まだ元の位置付近=塞いでいる)間は deadlyRadius 以内で Player に触れると死亡イベント発行。
properties = {
  { name = "axis",         type = "vec3",  default = {0, 1, 0},           label = "動く方向" },
  { name = "amplitude",    type = "float", default = 3.0, min = 0, max = 20, label = "先送りで動く量" },
  { name = "minOffset",    type = "float", default = 0.0,                 label = "offset下限" },
  { name = "deadlyRadius", type = "float", default = 0.9, min = 0, max = 5, label = "接触判定半径(0で無効)" },
  { name = "blockRatio",   type = "float", default = 0.5, min = 0, max = 1, label = "この割合未満のoffsetで塞ぐ判定" },
}

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
end

function OnUpdate(self, dt)
  self.transform.position = Vec3.new(
    self.bx + self.axis.x * self.offset,
    self.by + self.axis.y * self.offset,
    self.bz + self.axis.z * self.offset)

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
